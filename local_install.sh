#!/usr/bin/env sh
set -eu

usage() {
    cat <<EOF
Использование: $(basename "$0") [ФЛАГИ] [путь]

Собирает программу из локального git-репозитория и устанавливает бинарь.

  --user-only   установить в ~/.local/bin (без sudo); по умолчанию — /usr/local/bin
  -h, --help    эта справка

  [путь]  абсолютный путь к репозиторию или относительный — ищется по
          корням из ~/.config/install/roots.txt (дефолт: ~/tools).
          Если путь не указан, используется текущий каталог.

Требования к репозиторию:
  - содержит .git
  - содержит versions.txt с semver X.Y.Z
  - имя бинаря совпадает с именем каталога
  - есть таргет 'just build' (Justfile) или 'make build' (Makefile),
    который кладёт бинарь <имя> в корень репозитория
EOF
}

PROGRAM_PATH=""
USER_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --user-only) USER_ONLY=1; shift ;;
        -*) echo "Неизвестный флаг: $1" >&2; usage >&2; exit 1 ;;
        *)
            if [ -z "$PROGRAM_PATH" ]; then
                PROGRAM_PATH="$1"
            else
                echo "Ошибка: указан лишний аргумент: $1" >&2; usage >&2; exit 1
            fi
            shift ;;
    esac
done

# Путь не указан — берём текущий каталог
if [ -z "$PROGRAM_PATH" ]; then
    PROGRAM_PATH="$(pwd)"
fi

# --- вспомогательные функции ---

expand_tilde() {
    case "$1" in
        "~/"*) printf '%s' "$HOME/${1#~/}" ;;
        "~")   printf '%s' "$HOME" ;;
        *)     printf '%s' "$1" ;;
    esac
}

# Записывает список корней (по одному на строку) в файл $1
write_roots() {
    _out="$1"
    _roots_file="$HOME/.config/install/roots.txt"
    _found_any=0
    if [ -f "$_roots_file" ]; then
        while IFS= read -r _line; do
            case "$_line" in
                ""|\#*) continue ;;
            esac
            expand_tilde "$_line" >> "$_out"
            printf '\n' >> "$_out"
            _found_any=1
        done < "$_roots_file"
    fi
    if [ "$_found_any" = "0" ]; then
        printf '%s\n' "$HOME/tools" >> "$_out"
    fi
}

# --- резолв пути ---

case "$PROGRAM_PATH" in
    /*)
        REPO_DIR="$PROGRAM_PATH"
        ;;
    *)
        _roots_tmp=$(mktemp)
        write_roots "$_roots_tmp"
        REPO_DIR=""
        while IFS= read -r _root; do
            [ -z "$_root" ] && continue
            if [ -d "$_root/$PROGRAM_PATH" ]; then
                REPO_DIR="$_root/$PROGRAM_PATH"
                break
            fi
        done < "$_roots_tmp"
        if [ -z "$REPO_DIR" ]; then
            echo "Репозиторий '$PROGRAM_PATH' не найден. Просмотренные корни:" >&2
            while IFS= read -r _root; do
                [ -z "$_root" ] && continue
                echo "  $_root" >&2
            done < "$_roots_tmp"
            rm -f "$_roots_tmp"
            exit 1
        fi
        rm -f "$_roots_tmp"
        ;;
esac

# --- валидация ---

if [ ! -d "$REPO_DIR" ]; then
    echo "Ошибка: путь не является каталогом: $REPO_DIR" >&2; exit 1
fi

if [ ! -d "$REPO_DIR/.git" ]; then
    echo "Ошибка: $REPO_DIR не является git-репозиторием (нет .git)" >&2; exit 1
fi

if [ ! -f "$REPO_DIR/versions.txt" ]; then
    echo "Ошибка: не найден $REPO_DIR/versions.txt" >&2; exit 1
fi

# нормализуем путь к каталогу (для корректного basename имени бинаря)
REPO_DIR=$(cd "$REPO_DIR" && pwd)

# --- версия из versions.txt ---

VERSION=$(tr -d '[:space:]' < "$REPO_DIR/versions.txt")
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Ошибка: versions.txt должен содержать semver X.Y.Z (получено: '$VERSION')" >&2; exit 1
fi

# --- имя бинаря ---

BIN=$(basename "$REPO_DIR")

echo "Репозиторий:  $REPO_DIR"
echo "Бинарь:       $BIN"
echo "Версия:       $VERSION"

# --- сборка ---

BUILDER=""
BUILD_CMD=""

if command -v just >/dev/null 2>&1; then
    if [ -f "$REPO_DIR/Justfile" ] || [ -f "$REPO_DIR/justfile" ]; then
        BUILDER="just"
        BUILD_CMD="just build"
    fi
fi

if [ -z "$BUILDER" ]; then
    if [ -f "$REPO_DIR/Makefile" ] || [ -f "$REPO_DIR/makefile" ]; then
        BUILDER="make"
        BUILD_CMD="make build"
    fi
fi

if [ -z "$BUILDER" ]; then
    echo "Ошибка: не найден ни Justfile, ни Makefile в $REPO_DIR" >&2
    echo "Репозиторий должен содержать таргет 'just build' или 'make build'" >&2
    exit 1
fi

echo "Собираю: $BUILD_CMD (в $REPO_DIR)"
(cd "$REPO_DIR" && $BUILD_CMD)

# --- проверка собранного бинаря ---

BIN_PATH="$REPO_DIR/$BIN"
if [ ! -x "$BIN_PATH" ]; then
    echo "Ошибка: бинарь '$BIN' не найден в корне репозитория после сборки: $BIN_PATH" >&2
    echo "Таргет build должен класть исполняемый файл '$BIN' в корень репозитория" >&2
    exit 1
fi

# --- установка ---

if [ "$USER_ONLY" = "1" ]; then
    TARGET_DIR="$HOME/.local/bin"
else
    TARGET_DIR="/usr/local/bin"
fi

TARGET="$TARGET_DIR/$BIN"

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

echo "Установлено: $TARGET (версия $VERSION)"

case ":${PATH:-}:" in
    *":$TARGET_DIR:"*) ;;
    *)
        echo
        echo "Внимание: $TARGET_DIR отсутствует в PATH."
        echo "Добавьте в ~/.profile или ~/.bashrc / ~/.zshrc строку:"
        echo "    export PATH=\"$TARGET_DIR:\$PATH\""
        ;;
esac
