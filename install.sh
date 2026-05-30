#!/usr/bin/env sh
set -eu

usage() {
    cat <<EOF
Использование: $(basename "$0") [ФЛАГИ] <владелец/репозиторий> [имя-бинаря] [версия]

Скачивает и устанавливает go-программу из GitHub Releases.

  -i           выбрать версию интерактивно из списка
  -l, --list   вывести доступные версии и выйти
  -u, --update установить, только если доступная версия новее текущей
  -d, --dir DIR  каталог установки (переопределяет INSTALL_DIR)
  -h, --help   эта справка

  <владелец/репозиторий>  например: dimkarp93/envs
  [имя-бинаря]            имя исполняемого файла (по умолчанию: имя репозитория)
  [версия]                semver вида 1.2.3 или v1.2.3 (по умолчанию: latest); игнорируется при -i

Переменные среды:
  INSTALL_DIR     каталог установки (--dir имеет приоритет)
  INSTALL_FORCE=1 перезаписать без подтверждения
  GITHUB_TOKEN    токен GitHub: снимает лимит 60 req/h и разрешает
                  установку из приватных репозиториев
EOF
}

INTERACTIVE=0
LIST_ONLY=0
UPDATE_ONLY=0
REPO=""
BIN=""
VERSION=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -i) INTERACTIVE=1; shift ;;
        -l|--list) LIST_ONLY=1; shift ;;
        -u|--update) UPDATE_ONLY=1; shift ;;
        -d|--dir)
            if [ $# -lt 2 ]; then
                echo "Флаг --dir требует аргумент" >&2; exit 1
            fi
            INSTALL_DIR="$2"; shift 2 ;;
        --dir=*) INSTALL_DIR="${1#--dir=}"; shift ;;
        -*) echo "Неизвестный флаг: $1" >&2; usage >&2; exit 1 ;;
        *)
            if [ -z "$REPO" ]; then
                REPO="$1"
            elif [ -z "$BIN" ]; then
                BIN="$1"
            elif [ -z "$VERSION" ]; then
                VERSION="$1"
            fi
            shift ;;
    esac
done

if [ -z "$REPO" ]; then
    echo "Ошибка: укажите владелец/репозиторий" >&2
    usage >&2
    exit 1
fi

case "$REPO" in
    */*)  ;;
    *) echo "Ошибка: формат должен быть владелец/репозиторий (например, dimkarp93/envs)" >&2; exit 1 ;;
esac

if [ -z "$BIN" ]; then
    BIN="${REPO##*/}"
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "Требуется curl" >&2; exit 1
fi

case "$(uname -s)" in
    Linux)  OS=linux ;;
    Darwin) OS=darwin ;;
    *) echo "Неподдерживаемая ОС: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
    x86_64|amd64)   ARCH=amd64 ;;
    aarch64|arm64)  ARCH=arm64 ;;
    *) echo "Неподдерживаемая архитектура: $(uname -m)" >&2; exit 1 ;;
esac

auth_header() {
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        printf '%s' "-H \"Authorization: token $GITHUB_TOKEN\""
    fi
}

api_get() {
    _url="$1"
    _out=$(mktemp)
    _http=$(curl -o "$_out" -w "%{http_code}" -sSL \
        ${GITHUB_TOKEN:+-H "Authorization: token $GITHUB_TOKEN"} \
        "$_url" 2>/dev/null) || true
    if [ "$_http" != "200" ]; then
        cat "$_out" >&2 2>/dev/null || true
        rm -f "$_out"
        echo "GitHub API вернул HTTP $_http для $_url" >&2
        return 1
    fi
    cat "$_out"
    rm -f "$_out"
}

download_file() {
    _url="$1"
    _dest="$2"
    _show_progress="${3:-0}"
    if [ "$_show_progress" = "1" ]; then
        _progress="--progress-bar"
    else
        _progress="-sS"
    fi
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl -fL $_progress \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/octet-stream" \
            -o "$_dest" "$_url"
    else
        curl -fL $_progress -o "$_dest" "$_url"
    fi
}

list_versions() {
    api_get "https://api.github.com/repos/${REPO}/releases?per_page=100" \
        | grep '"tag_name":' \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

resolve_latest() {
    _json=$(api_get "https://api.github.com/repos/${REPO}/releases/latest") || return 1
    echo "$_json" | grep '"tag_name":' | head -1 \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

if [ "$LIST_ONLY" = "1" ]; then
    list_versions
    exit 0
fi

if [ "$INTERACTIVE" = "1" ]; then
    VERSIONS=$(list_versions)
    if [ -z "$VERSIONS" ]; then
        echo "Не удалось получить список версий" >&2; exit 1
    fi
    echo "Доступные версии:"
    i=1
    echo "$VERSIONS" | while IFS= read -r v; do
        printf "  %2d) %s\n" "$i" "$v"
        i=$((i + 1))
    done
    printf "Введите номер или версию: "
    read -r CHOICE
    case "$CHOICE" in
        ''|*[!0-9]*)
            case "$CHOICE" in
                v*) TAG="$CHOICE" ;;
                *)  TAG="v$CHOICE" ;;
            esac ;;
        *)
            TAG=$(echo "$VERSIONS" | sed -n "${CHOICE}p")
            if [ -z "$TAG" ]; then
                echo "Неверный номер: $CHOICE" >&2; exit 1
            fi ;;
    esac
elif [ -z "$VERSION" ]; then
    TAG=$(resolve_latest) || exit 1
    if [ -z "$TAG" ]; then
        echo "Не удалось определить последнюю версию" >&2; exit 1
    fi
else
    case "$VERSION" in
        v*) TAG="$VERSION" ;;
        *)  TAG="v$VERSION" ;;
    esac
fi

if [ "$UPDATE_ONLY" = "1" ]; then
    CURRENT=""
    if command -v "$BIN" >/dev/null 2>&1; then
        CURRENT=$("$BIN" --version 2>/dev/null || true)
    fi
    LATEST_VER="${TAG#v}"
    if [ "$CURRENT" = "$LATEST_VER" ]; then
        echo "$BIN уже актуален (версия $CURRENT)"
        exit 0
    fi
    echo "Обновление $BIN: $CURRENT -> $LATEST_VER"
fi

TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

ARCHIVE="${BIN}-${OS}-${ARCH}.tar.gz"
ARCHIVE_URL="https://github.com/${REPO}/releases/download/${TAG}/${ARCHIVE}"
SUMS_URL="https://github.com/${REPO}/releases/download/${TAG}/SHA256SUMS"

echo "Скачиваю $ARCHIVE_URL"
if ! download_file "$ARCHIVE_URL" "$TMPDIR/$ARCHIVE" 1; then
    echo "Не удалось скачать архив" >&2; exit 1
fi

echo "Скачиваю SHA256SUMS"
if ! download_file "$SUMS_URL" "$TMPDIR/SHA256SUMS"; then
    echo "Не удалось скачать SHA256SUMS" >&2; exit 1
fi

echo "Проверяю контрольную сумму"
if command -v sha256sum >/dev/null 2>&1; then
    (cd "$TMPDIR" && grep " ${ARCHIVE}$" SHA256SUMS | sha256sum -c --quiet -) || {
        echo "Проверка SHA256 не прошла — архив повреждён или подменён" >&2; exit 1
    }
elif command -v shasum >/dev/null 2>&1; then
    EXPECTED=$(grep " ${ARCHIVE}$" "$TMPDIR/SHA256SUMS" | awk '{print $1}')
    ACTUAL=$(shasum -a 256 "$TMPDIR/$ARCHIVE" | awk '{print $1}')
    if [ "$EXPECTED" != "$ACTUAL" ]; then
        echo "Проверка SHA256 не прошла — архив повреждён или подменён" >&2; exit 1
    fi
else
    echo "Внимание: sha256sum/shasum не найдены, проверка целостности пропущена" >&2
fi
echo "Контрольная сумма совпадает"

echo "Распаковываю"
tar -C "$TMPDIR" --no-same-owner -xzf "$TMPDIR/$ARCHIVE"

BIN_PATH=""
if [ -x "$TMPDIR/$BIN" ]; then
    BIN_PATH="$TMPDIR/$BIN"
elif [ -x "$TMPDIR/${BIN}-${OS}-${ARCH}/$BIN" ]; then
    BIN_PATH="$TMPDIR/${BIN}-${OS}-${ARCH}/$BIN"
fi

if [ -z "$BIN_PATH" ]; then
    echo "Исполняемый файл '$BIN' не найден в архиве" >&2; exit 1
fi
chmod +x "$BIN_PATH"

EXPECTED_VER="${TAG#v}"
ACTUAL_VER=$("$BIN_PATH" --version 2>/dev/null || true)
if [ -n "$ACTUAL_VER" ] && [ "$ACTUAL_VER" != "$EXPECTED_VER" ]; then
    echo "Внимание: версия бинаря ($ACTUAL_VER) не совпадает с тегом ($EXPECTED_VER)" >&2
fi

if [ -n "${INSTALL_DIR:-}" ]; then
    TARGET_DIR="$INSTALL_DIR"
else
    case "$OS" in
        linux)
            OPT1="/usr/bin"
            OPT2="/usr/local/bin"
            OPT3="$HOME/.local/bin"
            ;;
        darwin)
            OPT1="/usr/local/bin"
            OPT2="/opt/homebrew/bin"
            OPT3="$HOME/.local/bin"
            ;;
    esac
    echo "Куда установить $BIN?"
    echo "  1) $OPT1"
    echo "  2) $OPT2   (по умолчанию)"
    echo "  3) $OPT3"
    printf "Выберите [1-3]: "
    CHOICE=""
    read -r CHOICE || true
    CHOICE=${CHOICE:-2}
    case "$CHOICE" in
        1) TARGET_DIR="$OPT1" ;;
        2) TARGET_DIR="$OPT2" ;;
        3) TARGET_DIR="$OPT3" ;;
        *) echo "Некорректный выбор: $CHOICE" >&2; exit 1 ;;
    esac
fi

TARGET="$TARGET_DIR/$BIN"

if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
    if [ "${INSTALL_FORCE:-}" = "1" ]; then
        :
    else
        CUR_VER=""
        if [ -x "$TARGET" ]; then
            CUR_VER=$("$TARGET" --version 2>/dev/null || true)
        fi
        if [ -n "$CUR_VER" ]; then
            echo "Файл $TARGET уже существует (версия: $CUR_VER)."
        else
            echo "Файл $TARGET уже существует."
        fi
        printf "Перезаписать? [y/N]: "
        ANSWER=""
        read -r ANSWER || true
        case "$ANSWER" in
            y|Y|yes|YES) ;;
            *) echo "Установка отменена."; exit 1 ;;
        esac
    fi
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
$SUDO install -m 0755 "$BIN_PATH" "$TARGET"

echo "Установлено: $TARGET (версия ${ACTUAL_VER:-$EXPECTED_VER})"

case ":${PATH:-}:" in
    *":$TARGET_DIR:"*) ;;
    *)
        echo
        echo "Внимание: $TARGET_DIR отсутствует в PATH."
        echo "Добавьте в ~/.profile или ~/.bashrc / ~/.zshrc строку:"
        echo "    export PATH=\"$TARGET_DIR:\$PATH\""
        ;;
esac
