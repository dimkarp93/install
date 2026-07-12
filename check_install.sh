#!/usr/bin/env sh
set -eu

usage() {
    cat <<EOF
Использование: $(basename "$0") [ФЛАГИ] [путь]

Проверяет, соответствует ли репозиторий конвенциям из CONVENTIONS.md.

  --build       дополнительно собрать бинарь и проверить вывод --version
  -h, --help    эта справка

  [путь]  абсолютный путь к репозиторию или относительный — ищется по
          корням из ~/.config/install/roots.txt (дефолт: ~/tools).
          Если путь не указан, используется текущий каталог.

Код выхода 0 — все обязательные проверки пройдены; 1 — есть ошибки.
EOF
}

PROGRAM_PATH=""
DO_BUILD=0

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --build) DO_BUILD=1; shift ;;
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

ERRORS=0
WARNINGS=0
ok()   { printf '  [OK]   %s\n'   "$1"; }
warn() { printf '  [WARN] %s\n'   "$1"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf '  [FAIL] %s\n'   "$1"; ERRORS=$((ERRORS + 1)); }

# --- резолв пути (как в local_install.sh) ---

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

if [ ! -d "$REPO_DIR" ]; then
    echo "Ошибка: путь не является каталогом: $REPO_DIR" >&2; exit 1
fi
REPO_DIR=$(cd "$REPO_DIR" && pwd)

echo "Проверяю: $REPO_DIR"
echo

# --- git ---

echo "git-репозиторий:"
if [ -d "$REPO_DIR/.git" ]; then
    ok "найден .git"
else
    fail "нет каталога .git"
fi

# --- versions.txt ---

echo "Версия (versions.txt):"
if [ -f "$REPO_DIR/versions.txt" ]; then
    VERSION=$(tr -d '[:space:]' < "$REPO_DIR/versions.txt")
    if printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        ok "versions.txt = $VERSION (semver X.Y.Z)"
    else
        fail "versions.txt должен содержать semver X.Y.Z (получено: '$VERSION')"
        VERSION=""
    fi
else
    fail "нет versions.txt"
    VERSION=""
fi

# --- имя бинаря (имя каталога) ---

echo "Имя бинаря:"
BIN=$(basename "$REPO_DIR")
ok "имя бинаря из имени каталога = $BIN"

# --- build-таргет ---

echo "Сборка (build-таргет):"
HAS_JUST_FILE=0
HAS_MAKE_FILE=0
BUILD_FILE=""
if [ -f "$REPO_DIR/Justfile" ] || [ -f "$REPO_DIR/justfile" ]; then
    HAS_JUST_FILE=1
    [ -f "$REPO_DIR/Justfile" ] && BUILD_FILE="$REPO_DIR/Justfile" || BUILD_FILE="$REPO_DIR/justfile"
fi
if [ -f "$REPO_DIR/Makefile" ] || [ -f "$REPO_DIR/makefile" ]; then
    HAS_MAKE_FILE=1
    [ -z "$BUILD_FILE" ] && { [ -f "$REPO_DIR/Makefile" ] && BUILD_FILE="$REPO_DIR/Makefile" || BUILD_FILE="$REPO_DIR/makefile"; }
fi

if [ "$HAS_JUST_FILE" = "0" ] && [ "$HAS_MAKE_FILE" = "0" ]; then
    fail "нет Justfile и Makefile"
else
    if grep -Eq '^build( |:)' "$BUILD_FILE" 2>/dev/null; then
        ok "есть таргет build в $(basename "$BUILD_FILE")"
    else
        fail "в $(basename "$BUILD_FILE") нет таргета build"
    fi
    # bump-рецепты — рекомендация
    _missing=""
    for _r in bump-patch bump-minor bump-major; do
        grep -Eq "^${_r}( |:)" "$BUILD_FILE" 2>/dev/null || _missing="$_missing $_r"
    done
    if [ -z "$_missing" ]; then
        ok "есть рецепты bump-patch/bump-minor/bump-major"
    else
        warn "нет рецептов:$_missing"
    fi
fi

# --- release-workflow ---

echo "Release-workflow:"
_wf_found=0
for _f in "$REPO_DIR"/.github/workflows/*.yml "$REPO_DIR"/.github/workflows/*.yaml \
          "$REPO_DIR"/.gitea/workflows/*.yml "$REPO_DIR"/.gitea/workflows/*.yaml; do
    [ -f "$_f" ] || continue
    _wf_found=1
    break
done
if [ "$_wf_found" = "1" ]; then
    ok "найден .github/workflows/*.yml или .gitea/workflows/*.yml"
else
    warn "нет .github/workflows/*.yml и .gitea/workflows/*.yml (релиз не будет публиковаться автоматически)"
fi

# --- git-теги (рекомендация) ---

echo "Git-теги:"
if [ -d "$REPO_DIR/.git" ] && command -v git >/dev/null 2>&1; then
    _bad_tags=$(cd "$REPO_DIR" && git tag 2>/dev/null | grep -Ev '^v[0-9]+\.[0-9]+\.[0-9]+$' || true)
    _any_tags=$(cd "$REPO_DIR" && git tag 2>/dev/null | head -1 || true)
    if [ -z "$_any_tags" ]; then
        ok "тегов пока нет"
    elif [ -n "$_bad_tags" ]; then
        warn "есть теги не вида vMAJOR.MINOR.PATCH:"
        printf '%s\n' "$_bad_tags" | sed 's/^/         /'
    else
        ok "все теги вида vMAJOR.MINOR.PATCH"
    fi
else
    warn "git недоступен — теги не проверены"
fi

# --- опциональная сборка и проверка --version ---

if [ "$DO_BUILD" = "1" ]; then
    echo "Сборка и --version (--build):"
    BUILD_CMD=""
    if [ "$HAS_JUST_FILE" = "1" ] && command -v just >/dev/null 2>&1; then
        BUILD_CMD="just build"
    elif [ "$HAS_MAKE_FILE" = "1" ] && command -v make >/dev/null 2>&1; then
        BUILD_CMD="make build"
    fi
    if [ -z "$BUILD_CMD" ]; then
        warn "нет доступного сборщика (just/make) — сборка пропущена"
    elif (cd "$REPO_DIR" && $BUILD_CMD >/dev/null 2>&1); then
        BIN_PATH="$REPO_DIR/$BIN"
        if [ ! -x "$BIN_PATH" ]; then
            fail "бинарь '$BIN' не найден в корне репозитория после сборки"
        else
            ok "бинарь '$BIN' собран в корне репозитория"
            _ver=$("$BIN_PATH" --version 2>/dev/null || true)
            if [ -z "$_ver" ]; then
                fail "--version ничего не вывел"
            elif [ -n "$VERSION" ] && [ "$_ver" != "$VERSION" ]; then
                fail "--version вывел '$_ver', ожидалось '$VERSION' (из versions.txt)"
            else
                ok "--version = $_ver"
            fi
        fi
    else
        fail "сборка ($BUILD_CMD) завершилась с ошибкой"
    fi
fi

# --- итог ---

echo
if [ "$ERRORS" -eq 0 ]; then
    if [ "$WARNINGS" -eq 0 ]; then
        echo "Готово: репозиторий полностью соответствует конвенциям."
    else
        echo "Готово: обязательные требования выполнены, предупреждений — $WARNINGS."
    fi
    exit 0
else
    echo "Не пройдено: ошибок — $ERRORS, предупреждений — $WARNINGS."
    exit 1
fi
