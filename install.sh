#!/usr/bin/env sh
set -eu

usage() {
    cat <<EOF
Использование: $(basename "$0") [ФЛАГИ] <владелец/репозиторий> [имя-бинаря] [версия]
         или: $(basename "$0") -F <архив.tar.gz> [имя-бинаря]

Скачивает и устанавливает go-программу из GitHub Releases.

  -i               выбрать версию интерактивно из списка
  -l, --list       вывести доступные версии и выйти
  -u, --update     установить, только если доступная версия новее текущей
  -D, --download   только скачать архив + SHA256SUMS и проверить сумму;
                   вывести путь до архива; каталог задаётся через -d/INSTALL_DIR
                   (по умолчанию: текущий каталог)
  -F, --from-file  установить из локального архива (проверив SHA256SUMS рядом);
                   игнорирует версию, -i, -u; имя-бинаря берётся из имени файла
  -d, --dir DIR    каталог установки (переопределяет INSTALL_DIR)
  -h, --help       эта справка

  <владелец/репозиторий>  например: dimkarp93/envs
  [имя-бинаря]            имя исполняемого файла (по умолчанию: имя репозитория)
  [версия]                semver вида 1.2.3 или v1.2.3 (по умолчанию: latest)

Переменные среды:
  INSTALL_DIR     каталог установки / каталог для скачивания (-d имеет приоритет)
  INSTALL_FORCE=1 перезаписать без подтверждения
  GITHUB_TOKEN    токен GitHub: снимает лимит 60 req/h и разрешает
                  установку из приватных репозиториев
EOF
}

INTERACTIVE=0
LIST_ONLY=0
UPDATE_ONLY=0
DOWNLOAD_ONLY=0
FROM_FILE=""
REPO=""
BIN=""
VERSION=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -i) INTERACTIVE=1; shift ;;
        -l|--list) LIST_ONLY=1; shift ;;
        -u|--update) UPDATE_ONLY=1; shift ;;
        -D|--download) DOWNLOAD_ONLY=1; shift ;;
        -F|--from-file)
            if [ $# -lt 2 ]; then
                echo "Флаг --from-file требует аргумент" >&2; exit 1
            fi
            FROM_FILE="$2"; shift 2 ;;
        --from-file=*) FROM_FILE="${1#--from-file=}"; shift ;;
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

# --- валидация аргументов ---

if [ -n "$FROM_FILE" ]; then
    if [ ! -f "$FROM_FILE" ]; then
        echo "Файл не найден: $FROM_FILE" >&2; exit 1
    fi
    # первый позиционный (REPO) без '/' трактуем как имя бинаря
    if [ -n "$REPO" ] && [ -z "$BIN" ]; then
        case "$REPO" in
            */*) ;;
            *) BIN="$REPO" ;;
        esac
    fi
    if [ -z "$BIN" ]; then
        _base=$(basename "$FROM_FILE" .tar.gz)
        BIN="${_base%-${OS}-${ARCH}}"
        if [ -z "$BIN" ] || [ "$BIN" = "$(basename "$FROM_FILE" .tar.gz)" ]; then
            echo "Не удалось определить имя бинаря из имени файла: $(basename "$FROM_FILE")" >&2
            echo "Укажите имя явно: $(basename "$0") -F $FROM_FILE <имя-бинаря>" >&2
            exit 1
        fi
    fi
else
    if [ -z "$REPO" ]; then
        echo "Ошибка: укажите владелец/репозиторий" >&2
        usage >&2; exit 1
    fi
    case "$REPO" in
        */*)  ;;
        *) echo "Ошибка: формат должен быть владелец/репозиторий (например, dimkarp93/envs)" >&2; exit 1 ;;
    esac
fi

# --- вспомогательные функции ---

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

check_sha256() {
    _archive="$1"
    _sums="$2"
    _name=$(basename "$_archive")
    if command -v sha256sum >/dev/null 2>&1; then
        _dir=$(dirname "$_archive")
        (cd "$_dir" && grep " ${_name}$" "$_sums" | sha256sum -c --quiet -) || {
            echo "Проверка SHA256 не прошла — архив повреждён или подменён" >&2; return 1
        }
    elif command -v shasum >/dev/null 2>&1; then
        _expected=$(grep " ${_name}$" "$_sums" | awk '{print $1}')
        _actual=$(shasum -a 256 "$_archive" | awk '{print $1}')
        if [ "$_expected" != "$_actual" ]; then
            echo "Проверка SHA256 не прошла — архив повреждён или подменён" >&2; return 1
        fi
    else
        echo "Внимание: sha256sum/shasum не найдены, проверка целостности пропущена" >&2
    fi
    echo "Контрольная сумма совпадает"
}

list_versions() {
    _json=$(api_get "https://api.github.com/repos/${REPO}/releases?per_page=100") || return 1
    echo "$_json" \
        | grep '"tag_name":' \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

get_release() {
    _tag="${1:-}"
    if [ -z "$_tag" ]; then
        api_get "https://api.github.com/repos/${REPO}/releases/latest"
    else
        api_get "https://api.github.com/repos/${REPO}/releases/tags/${_tag}"
    fi
}

discover_bin() {
    echo "$1" | grep '"name":' \
        | grep "\"[^\"]*-${OS}-${ARCH}\.tar\.gz\"" \
        | sed -E 's/.*"name": *"([^"]+)".*/\1/' \
        | head -1 \
        | sed -E "s/-${OS}-${ARCH}\\.tar\\.gz\$//"
}

# Достаёт API-URL ассета (https://api.github.com/.../releases/assets/<id>)
# по его имени из JSON релиза. Нужен для приватных репозиториев: ссылка
# browser_download_url (github.com/.../releases/download/...) не принимает
# токен и отдаёт 404, а API-эндпоинт с Accept: application/octet-stream — да.
# Расчёт на то, что GitHub возвращает по одному полю на строку и поле "url"
# ассета идёт перед его "name".
asset_api_url() {
    echo "$RELEASE_JSON" | awk -v target="$1" '
        /"url":/  { url = $0 }
        /"name":/ {
            name = $0
            sub(/.*"name": *"/, "", name); sub(/".*/, "", name)
            if (name == target) {
                sub(/.*"url": *"/, "", url); sub(/".*/, "", url)
                print url
                exit
            }
        }
    '
}

do_install() {
    _bin_path="$1"
    _bin_ver="${2:-}"

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
        read -r CHOICE </dev/tty || true
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
        if [ "${INSTALL_FORCE:-}" != "1" ]; then
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
            read -r ANSWER </dev/tty || true
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
    $SUDO install -m 0755 "$_bin_path" "$TARGET"

    echo "Установлено: $TARGET${_bin_ver:+ (версия $_bin_ver)}"

    case ":${PATH:-}:" in
        *":$TARGET_DIR:"*) ;;
        *)
            echo
            echo "Внимание: $TARGET_DIR отсутствует в PATH."
            echo "Добавьте в ~/.profile или ~/.bashrc / ~/.zshrc строку:"
            echo "    export PATH=\"$TARGET_DIR:\$PATH\""
            ;;
    esac
}

extract_bin() {
    _archive="$1"
    _workdir="$2"
    tar -C "$_workdir" --no-same-owner -xzf "$_archive"
    if [ -x "$_workdir/$BIN" ]; then
        echo "$_workdir/$BIN"
    elif [ -x "$_workdir/${BIN}-${OS}-${ARCH}/$BIN" ]; then
        echo "$_workdir/${BIN}-${OS}-${ARCH}/$BIN"
    else
        echo "Исполняемый файл '$BIN' не найден в архиве" >&2; return 1
    fi
}

# --- режим: только список версий ---

if [ "$LIST_ONLY" = "1" ]; then
    VERSIONS=$(list_versions) || exit 1
    if [ -z "$VERSIONS" ]; then
        echo "У репозитория ${REPO} нет релизов" >&2; exit 1
    fi
    echo "$VERSIONS"
    exit 0
fi

# --- режим: установка из локального архива ---

if [ -n "$FROM_FILE" ]; then
    ARCHIVE_PATH=$(cd "$(dirname "$FROM_FILE")" && pwd)/$(basename "$FROM_FILE")
    SUMS_PATH="$(dirname "$ARCHIVE_PATH")/SHA256SUMS"

    if [ ! -f "$SUMS_PATH" ]; then
        echo "Не найден SHA256SUMS рядом с архивом: $SUMS_PATH" >&2; exit 1
    fi

    echo "Проверяю контрольную сумму $ARCHIVE_PATH"
    check_sha256 "$ARCHIVE_PATH" "$SUMS_PATH" || exit 1

    WORKDIR=$(mktemp -d)
    trap 'rm -rf "$WORKDIR"' EXIT

    echo "Распаковываю"
    BIN_PATH=$(extract_bin "$ARCHIVE_PATH" "$WORKDIR") || exit 1
    chmod +x "$BIN_PATH"

    BIN_VER=$("$BIN_PATH" --version 2>/dev/null || true)
    do_install "$BIN_PATH" "$BIN_VER"
    exit 0
fi

# --- разрешение тега (сетевые режимы) ---

RELEASE_JSON=""

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
    read -r CHOICE </dev/tty
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
    RELEASE_JSON=$(get_release) || exit 1
    TAG=$(echo "$RELEASE_JSON" | grep '"tag_name":' | head -1 \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
    if [ -z "$TAG" ]; then
        echo "Не удалось определить последнюю версию" >&2; exit 1
    fi
else
    case "$VERSION" in
        v*) TAG="$VERSION" ;;
        *)  TAG="v$VERSION" ;;
    esac
fi

# --- автообнаружение имени бинаря из ассетов релиза ---

if [ -z "$BIN" ]; then
    if [ -z "$RELEASE_JSON" ]; then
        RELEASE_JSON=$(get_release "$TAG") || exit 1
    fi
    BIN=$(discover_bin "$RELEASE_JSON")
    if [ -z "$BIN" ]; then
        echo "Не найден ассет *-${OS}-${ARCH}.tar.gz в релизе ${TAG}" >&2
        echo "Укажите имя бинаря явно: $(basename "$0") $REPO <имя-бинаря>" >&2
        exit 1
    fi
fi

ARCHIVE="${BIN}-${OS}-${ARCH}.tar.gz"

# Для приватных репозиториев прямой browser_download_url не принимает токен —
# качаем через API asset endpoint. Для публичных оставляем простую ссылку.
if [ -n "${GITHUB_TOKEN:-}" ]; then
    if [ -z "$RELEASE_JSON" ]; then
        RELEASE_JSON=$(get_release "$TAG") || exit 1
    fi
    ARCHIVE_URL=$(asset_api_url "$ARCHIVE")
    SUMS_URL=$(asset_api_url "SHA256SUMS")
    if [ -z "$ARCHIVE_URL" ]; then
        echo "Ассет $ARCHIVE не найден в релизе ${TAG}" >&2; exit 1
    fi
    if [ -z "$SUMS_URL" ]; then
        echo "Ассет SHA256SUMS не найден в релизе ${TAG}" >&2; exit 1
    fi
else
    ARCHIVE_URL="https://github.com/${REPO}/releases/download/${TAG}/${ARCHIVE}"
    SUMS_URL="https://github.com/${REPO}/releases/download/${TAG}/SHA256SUMS"
fi

# --- режим: только скачать ---

if [ "$DOWNLOAD_ONLY" = "1" ]; then
    DEST_DIR="${INSTALL_DIR:-$(pwd)}"
    mkdir -p "$DEST_DIR"

    echo "Скачиваю $ARCHIVE_URL"
    if ! download_file "$ARCHIVE_URL" "$DEST_DIR/$ARCHIVE" 1; then
        echo "Не удалось скачать архив" >&2; exit 1
    fi

    echo "Скачиваю SHA256SUMS"
    if ! download_file "$SUMS_URL" "$DEST_DIR/SHA256SUMS"; then
        echo "Не удалось скачать SHA256SUMS" >&2; exit 1
    fi

    check_sha256 "$DEST_DIR/$ARCHIVE" "$DEST_DIR/SHA256SUMS" || {
        rm -f "$DEST_DIR/$ARCHIVE" "$DEST_DIR/SHA256SUMS"
        exit 1
    }

    # единственный вывод в stdout — путь до архива (остальное шло в stderr через echo)
    DEST_ABS=$(cd "$DEST_DIR" && pwd)/$ARCHIVE
    echo "$DEST_ABS"
    exit 0
fi

# --- режим: полная установка ---

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

echo "Скачиваю $ARCHIVE_URL"
if ! download_file "$ARCHIVE_URL" "$TMPDIR/$ARCHIVE" 1; then
    echo "Не удалось скачать архив" >&2; exit 1
fi

echo "Скачиваю SHA256SUMS"
if ! download_file "$SUMS_URL" "$TMPDIR/SHA256SUMS"; then
    echo "Не удалось скачать SHA256SUMS" >&2; exit 1
fi

echo "Проверяю контрольную сумму"
check_sha256 "$TMPDIR/$ARCHIVE" "$TMPDIR/SHA256SUMS" || exit 1

echo "Распаковываю"
BIN_PATH=$(extract_bin "$TMPDIR/$ARCHIVE" "$TMPDIR") || exit 1
chmod +x "$BIN_PATH"

EXPECTED_VER="${TAG#v}"
ACTUAL_VER=$("$BIN_PATH" --version 2>/dev/null || true)
if [ -n "$ACTUAL_VER" ] && [ "$ACTUAL_VER" != "$EXPECTED_VER" ]; then
    echo "Внимание: версия бинаря ($ACTUAL_VER) не совпадает с тегом ($EXPECTED_VER)" >&2
fi

do_install "$BIN_PATH" "${ACTUAL_VER:-$EXPECTED_VER}"
