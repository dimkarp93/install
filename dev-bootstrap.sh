#!/usr/bin/env sh
set -eu

# dev-аналог bootstrap.sh: ставит установщики не из GitHub, а из текущей
# рабочей копии этого репозитория (рядом с этим скриптом). Удобно при правке
# самих установщиков — поправил → dev-bootstrap.sh → проверил в PATH.

SCRIPTS="github_install.sh gitea_install.sh local_install.sh go_install.sh check_install.sh"

usage() {
    cat <<EOF
Использование: $(basename "$0") [ФЛАГИ]

Копирует установщики (${SCRIPTS}) из текущей рабочей копии в PATH.

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

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# проверяем, что исходники на месте
for _name in $SCRIPTS; do
    if [ ! -f "$SCRIPT_DIR/$_name" ]; then
        echo "Не найден $SCRIPT_DIR/$_name — запускайте dev-bootstrap.sh из рабочей копии install" >&2
        exit 1
    fi
done

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

for _name in $SCRIPTS; do
    $SUDO install -m 0755 "$SCRIPT_DIR/$_name" "$TARGET_DIR/$_name"
    echo "Установлено: $TARGET_DIR/$_name (из $SCRIPT_DIR/$_name)"
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
