#!/usr/bin/env sh
set -eu

REPO="dimkarp93/install"
BRANCH="master"
SCRIPTS="github_install.sh gitea_install.sh local_install.sh go_install.sh check_install.sh"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

usage() {
    cat <<EOF
Использование: $(basename "$0") [ФЛАГИ]

Скачивает установщики (${SCRIPTS}) и кладёт их в PATH.

  --user-only   установить в ~/.local/bin (без sudo); по умолчанию — /usr/local/bin
  -h, --help    эта справка
EOF
}

USER_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --user-only) USER_ONLY=1; shift ;;
        *) echo "Неизвестный флаг: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if ! command -v curl >/dev/null 2>&1; then
    echo "Требуется curl" >&2; exit 1
fi

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

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

for _name in $SCRIPTS; do
    _url="${BASE_URL}/${_name}"
    echo "Скачиваю $_url"
    if ! curl -fsSL -o "$TMPFILE" "$_url"; then
        echo "Не удалось скачать $_name" >&2; exit 1
    fi
    $SUDO install -m 0755 "$TMPFILE" "$TARGET_DIR/$_name"
    echo "Установлено: $TARGET_DIR/$_name"
done

case ":${PATH:-}:" in
    *":$TARGET_DIR:"*) ;;
    *)
        echo
        echo "Внимание: $TARGET_DIR отсутствует в PATH."
        echo "Добавьте в ~/.profile или ~/.bashrc / ~/.zshrc строку:"
        echo "    export PATH=\"$TARGET_DIR:\$PATH\""
        ;;
esac
