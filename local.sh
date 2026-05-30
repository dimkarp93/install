#!/usr/bin/env sh
set -eu

REPO="dimkarp93/install_scripts"
BRANCH="master"
TARGET_NAME="github_install.sh"
SRC_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/install.sh"

if ! command -v curl >/dev/null 2>&1; then
    echo "Требуется curl" >&2; exit 1
fi

OS=$(uname -s)
case "$OS" in
    Linux)
        OPT1="/usr/bin"
        OPT2="/usr/local/bin"
        OPT3="$HOME/.local/bin"
        ;;
    Darwin)
        OPT1="/usr/local/bin"
        OPT2="/opt/homebrew/bin"
        OPT3="$HOME/.local/bin"
        ;;
    *)
        echo "Неподдерживаемая ОС: $OS" >&2; exit 1 ;;
esac

echo "Куда установить $TARGET_NAME?"
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

TARGET="$TARGET_DIR/$TARGET_NAME"

if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
    printf "Файл %s уже существует. Перезаписать? [y/N]: " "$TARGET"
    ANSWER=""
    read -r ANSWER || true
    case "$ANSWER" in
        y|Y|yes|YES) ;;
        *) echo "Установка отменена."; exit 1 ;;
    esac
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

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

echo "Скачиваю $SRC_URL"
if ! curl -fsSL -o "$TMPFILE" "$SRC_URL"; then
    echo "Не удалось скачать install.sh" >&2; exit 1
fi

$SUDO mkdir -p "$TARGET_DIR"
$SUDO install -m 0755 "$TMPFILE" "$TARGET"

echo "Установлено: $TARGET"

case ":${PATH:-}:" in
    *":$TARGET_DIR:"*) ;;
    *)
        echo
        echo "Внимание: $TARGET_DIR отсутствует в PATH."
        echo "Добавьте в ~/.profile или ~/.bashrc / ~/.zshrc строку:"
        echo "    export PATH=\"$TARGET_DIR:\$PATH\""
        ;;
esac
