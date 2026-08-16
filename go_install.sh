#!/usr/bin/env sh
set -eu

usage() {
    cat <<EOF
Использование: $(basename "$0") [ФЛАГИ] <module-path> [версия]

Устанавливает Go-программу через 'go install' и кладёт бинарь в PATH.

  -l, --list       вывести доступные версии модуля и выйти
  -p, --pkg ПУТЬ   путь пакета внутри модуля (по умолчанию определяется
                   автоматически: <module>/cmd/<имя>, затем <module>)
  --gobin          оставить бинарь в GOBIN (~/go/bin), не копировать в PATH
  --user-only      установить в ~/.local/bin (без sudo); по умолчанию — /usr/local/bin
  -h, --help       эта справка

  <module-path>  путь модуля, например: github.com/dimkarp93/md-pdf
  [версия]       semver вида 1.2.3 или v1.2.3 (по умолчанию: latest)

Требует установленного Go. Модуль должен соответствовать Go-конвенциям из
CONVENTIONS.md: сетевой module path, зависимости опубликованы, без replace в go.mod.
Если Go нет или программа написана не на Go — используйте github_install.sh или
gitea_install.sh.

Флаги -D, -F, -i, -u не поддерживаются: у 'go install' нет промежуточного архива.
Для этих сценариев используйте github_install.sh / gitea_install.sh.

  GOPRIVATE  для приватных репозиториев, например: GOPRIVATE=github.com/dimkarp93/*
EOF
}

MODULE=""
VERSION_ARG=""
PKG=""
LIST_ONLY=0
KEEP_GOBIN=0
USER_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -l|--list) LIST_ONLY=1; shift ;;
        --gobin) KEEP_GOBIN=1; shift ;;
        --user-only) USER_ONLY=1; shift ;;
        -p|--pkg)
            if [ $# -lt 2 ]; then
                echo "Флаг --pkg требует аргумент" >&2; exit 1
            fi
            PKG="$2"; shift 2 ;;
        --pkg=*) PKG="${1#--pkg=}"; shift ;;
        -*) echo "Неизвестный флаг: $1" >&2; usage >&2; exit 1 ;;
        *)
            if [ -z "$MODULE" ]; then
                MODULE="$1"
            elif [ -z "$VERSION_ARG" ]; then
                VERSION_ARG="$1"
            else
                echo "Ошибка: указан лишний аргумент: $1" >&2; usage >&2; exit 1
            fi
            shift ;;
    esac
done

if [ -z "$MODULE" ]; then
    echo "Ошибка: не указан module-path" >&2; usage >&2; exit 1
fi

MODULE=${MODULE%/}

if ! command -v go >/dev/null 2>&1; then
    echo "Ошибка: не найден 'go' в PATH — go_install.sh требует установленного Go." >&2
    echo "Установите Go (https://go.dev/dl/) или воспользуйтесь github_install.sh /" >&2
    echo "gitea_install.sh — они ставят готовый бинарь и Go не требуют." >&2
    exit 1
fi

case "$MODULE" in
    */*) ;;
    *)
        echo "Ошибка: '$MODULE' не похож на module-path." >&2
        echo "Ожидается сетевой путь вида github.com/owner/repo (см. CONVENTIONS.md)." >&2
        exit 1 ;;
esac

private_hint() {
    if [ -z "${GOPRIVATE:-}" ]; then
        echo "Если репозиторий приватный — задайте GOPRIVATE, например:" >&2
        echo "    GOPRIVATE=$(printf '%s' "$MODULE" | cut -d/ -f1-2)/* $(basename "$0") $MODULE" >&2
        echo "и настройте доступ git к репозиторию (SSH-ключ или ~/.netrc)." >&2
    else
        echo "GOPRIVATE=$GOPRIVATE задан — проверьте доступ git к репозиторию" >&2
        echo "(SSH-ключ, ~/.netrc или git config url.<...>.insteadOf)." >&2
    fi
}

if [ "$LIST_ONLY" = "1" ]; then
    _versions=$(go list -m -versions "$MODULE" 2>/dev/null) || {
        echo "Не удалось получить список версий модуля $MODULE" >&2
        private_hint
        exit 1
    }
    _versions=$(printf '%s' "$_versions" | cut -s -d' ' -f2-)
    if [ -z "$_versions" ]; then
        echo "У модуля $MODULE нет опубликованных версий (нет semver-тегов)" >&2
        exit 1
    fi
    printf '%s' "$_versions" | tr ' ' '\n'
    exit 0
fi

if [ -z "$VERSION_ARG" ] || [ "$VERSION_ARG" = "latest" ]; then
    VERSION="latest"
else
    VERSION="${VERSION_ARG#v}"
    if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "Ошибка: версия должна быть semver X.Y.Z или vX.Y.Z (получено: '$VERSION_ARG')" >&2
        exit 1
    fi
    VERSION="v$VERSION"
fi

BIN=$(basename "$MODULE")
case "$BIN" in
    v[0-9]|v[0-9][0-9]) BIN=$(basename "$(dirname "$MODULE")") ;;
esac

if [ -n "$PKG" ]; then
    CANDIDATES="$PKG"
    BIN=$(basename "$PKG")
else
    CANDIDATES="$MODULE/cmd/$BIN $MODULE"
fi

GOBIN_TMP=$(mktemp -d)
trap 'rm -rf "$GOBIN_TMP"' EXIT

echo "Модуль:       $MODULE"
echo "Версия:       $VERSION"

INSTALL_LOG=$(mktemp)
trap 'rm -rf "$GOBIN_TMP"; rm -f "$INSTALL_LOG"' EXIT

INSTALLED_PKG=""
for _pkg in $CANDIDATES; do
    echo "Пробую:       go install $_pkg@$VERSION"
    if GOBIN="$GOBIN_TMP" go install -trimpath "$_pkg@$VERSION" >"$INSTALL_LOG" 2>&1; then
        INSTALLED_PKG="$_pkg"
        break
    fi
done

if [ -z "$INSTALLED_PKG" ]; then
    echo "Ошибка: не удалось установить $MODULE@$VERSION" >&2
    cat "$INSTALL_LOG" >&2
    if grep -qiE '404|not found|unrecognized import|terminal prompts disabled|authentication' "$INSTALL_LOG"; then
        private_hint
    fi
    exit 1
fi

BUILT=$(find "$GOBIN_TMP" -maxdepth 1 -type f | head -1)
if [ -z "$BUILT" ]; then
    echo "Ошибка: go install отработал, но бинарь не найден в $GOBIN_TMP" >&2
    exit 1
fi

BIN=$(basename "$BUILT")

ACTUAL_VERSION=$(go version -m "$BUILT" 2>/dev/null \
    | awk '$1 == "mod" { print $3; exit }')
[ -n "$ACTUAL_VERSION" ] || ACTUAL_VERSION="$VERSION"

echo "Пакет:        $INSTALLED_PKG"
echo "Бинарь:       $BIN"

if [ "$KEEP_GOBIN" = "1" ]; then
    TARGET_DIR=$(go env GOBIN)
    if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$(go env GOPATH)/bin"
    fi
    mkdir -p "$TARGET_DIR"
    install -m 0755 "$BUILT" "$TARGET_DIR/$BIN"
    echo "Установлено: $TARGET_DIR/$BIN (версия $ACTUAL_VERSION)"
else
    if [ "$USER_ONLY" = "1" ]; then
        TARGET_DIR="$HOME/.local/bin"
    else
        TARGET_DIR="/usr/local/bin"
    fi

    if [ -w "$TARGET_DIR" ] || { [ ! -e "$TARGET_DIR" ] && mkdir -p "$TARGET_DIR" 2>/dev/null; }; then
        SUDO=""
    else
        if command -v sudo >/dev/null 2>&1; then
            SUDO="sudo"
        else
            echo "Каталог $TARGET_DIR недоступен на запись и sudo не найден." >&2; exit 1
        fi
    fi

    $SUDO mkdir -p "$TARGET_DIR"
    $SUDO install -m 0755 "$BUILT" "$TARGET_DIR/$BIN"
    echo "Установлено: $TARGET_DIR/$BIN (версия $ACTUAL_VERSION)"
fi

case ":${PATH:-}:" in
    *":$TARGET_DIR:"*) ;;
    *)
        echo
        echo "Внимание: $TARGET_DIR отсутствует в PATH."
        echo "Добавьте в ~/.profile или ~/.bashrc / ~/.zshrc строку:"
        echo "    export PATH=\"$TARGET_DIR:\$PATH\""
        ;;
esac
