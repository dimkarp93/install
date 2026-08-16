#!/usr/bin/env sh
set -eu

usage() {
    cat <<EOF
Usage: $(basename "$0") [FLAGS] [path]

Checks whether a repository follows the conventions from CONVENTIONS.md.

  --build       additionally build the binary and check its --version output
  -h, --help    show this help

  [path]  absolute path to the repository, or a relative one - looked up in
          the roots from ~/.config/install/roots.txt (default: ~/tools).
          If no path is given, the current directory is used.

Exit code 0 - all required checks passed; 1 - there are errors.
EOF
}

PROGRAM_PATH=""
DO_BUILD=0

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --build) DO_BUILD=1; shift ;;
        -*) echo "Unknown flag: $1" >&2; usage >&2; exit 1 ;;
        *)
            if [ -z "$PROGRAM_PATH" ]; then
                PROGRAM_PATH="$1"
            else
                echo "Error: unexpected extra argument: $1" >&2; usage >&2; exit 1
            fi
            shift ;;
    esac
done

if [ -z "$PROGRAM_PATH" ]; then
    PROGRAM_PATH="$(pwd)"
fi

# --- helpers ---

expand_tilde() {
    case "$1" in
        "~/"*) printf '%s' "$HOME/${1#~/}" ;;
        "~")   printf '%s' "$HOME" ;;
        *)     printf '%s' "$1" ;;
    esac
}

# Writes the list of roots (one per line) into file $1
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

# --- path resolution (same as in local_install.sh) ---

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
            echo "Repository '$PROGRAM_PATH' not found. Roots searched:" >&2
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
    echo "Error: path is not a directory: $REPO_DIR" >&2; exit 1
fi
REPO_DIR=$(cd "$REPO_DIR" && pwd)

echo "Checking: $REPO_DIR"
echo

# --- git ---

echo "git repository:"
if [ -d "$REPO_DIR/.git" ]; then
    ok ".git found"
else
    fail "no .git directory"
fi

# --- versions.txt ---

echo "Version (versions.txt):"
if [ -f "$REPO_DIR/versions.txt" ]; then
    VERSION=$(tr -d '[:space:]' < "$REPO_DIR/versions.txt")
    if printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        ok "versions.txt = $VERSION (semver X.Y.Z)"
    else
        fail "versions.txt must contain semver X.Y.Z (got: '$VERSION')"
        VERSION=""
    fi
else
    fail "no versions.txt"
    VERSION=""
fi

# --- binary name (directory name) ---

echo "Binary name:"
BIN=$(basename "$REPO_DIR")
ok "binary name from directory name = $BIN"

# --- build target ---

echo "Build (build target):"
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
    fail "neither Justfile nor Makefile"
else
    if grep -Eq '^build( |:)' "$BUILD_FILE" 2>/dev/null; then
        ok "build target present in $(basename "$BUILD_FILE")"
    else
        fail "no build target in $(basename "$BUILD_FILE")"
    fi
    # bump recipes - recommended
    _missing=""
    for _r in bump-patch bump-minor bump-major; do
        grep -Eq "^${_r}( |:)" "$BUILD_FILE" 2>/dev/null || _missing="$_missing $_r"
    done
    if [ -z "$_missing" ]; then
        ok "bump-patch/bump-minor/bump-major recipes present"
    else
        warn "missing recipes:$_missing"
    fi
fi

# --- release-workflow ---

echo "Release workflow:"
_wf_found=0
for _f in "$REPO_DIR"/.github/workflows/*.yml "$REPO_DIR"/.github/workflows/*.yaml \
          "$REPO_DIR"/.gitea/workflows/*.yml "$REPO_DIR"/.gitea/workflows/*.yaml; do
    [ -f "$_f" ] || continue
    _wf_found=1
    break
done
if [ "$_wf_found" = "1" ]; then
    ok ".github/workflows/*.yml or .gitea/workflows/*.yml found"
else
    warn "no .github/workflows/*.yml and no .gitea/workflows/*.yml (releases will not be published automatically)"
fi

# --- git tags (recommended) ---

echo "Git tags:"
if [ -d "$REPO_DIR/.git" ] && command -v git >/dev/null 2>&1; then
    _bad_tags=$(cd "$REPO_DIR" && git tag 2>/dev/null | grep -Ev '^v[0-9]+\.[0-9]+\.[0-9]+$' || true)
    _any_tags=$(cd "$REPO_DIR" && git tag 2>/dev/null | head -1 || true)
    if [ -z "$_any_tags" ]; then
        ok "no tags yet"
    elif [ -n "$_bad_tags" ]; then
        warn "there are tags not shaped like vMAJOR.MINOR.PATCH:"
        printf '%s\n' "$_bad_tags" | sed 's/^/         /'
    else
        ok "all tags shaped like vMAJOR.MINOR.PATCH"
    fi
else
    warn "git is unavailable - tags were not checked"
fi

# --- optional build and --version check ---

if [ "$DO_BUILD" = "1" ]; then
    echo "Build and --version (--build):"
    BUILD_CMD=""
    if [ "$HAS_JUST_FILE" = "1" ] && command -v just >/dev/null 2>&1; then
        BUILD_CMD="just build"
    elif [ "$HAS_MAKE_FILE" = "1" ] && command -v make >/dev/null 2>&1; then
        BUILD_CMD="make build"
    fi
    if [ -z "$BUILD_CMD" ]; then
        warn "no available builder (just/make) - build skipped"
    elif (cd "$REPO_DIR" && $BUILD_CMD >/dev/null 2>&1); then
        BIN_PATH="$REPO_DIR/$BIN"
        if [ ! -x "$BIN_PATH" ]; then
            fail "binary '$BIN' not found in the repository root after the build"
        else
            ok "binary '$BIN' built in the repository root"
            _ver=$("$BIN_PATH" --version 2>/dev/null || true)
            if [ -z "$_ver" ]; then
                fail "--version printed nothing"
            elif [ -n "$VERSION" ] && [ "$_ver" != "$VERSION" ]; then
                fail "--version printed '$_ver', expected '$VERSION' (from versions.txt)"
            else
                ok "--version = $_ver"
            fi
        fi
    else
        fail "the build ($BUILD_CMD) failed"
    fi
fi

# --- summary ---

echo
if [ "$ERRORS" -eq 0 ]; then
    if [ "$WARNINGS" -eq 0 ]; then
        echo "Done: the repository fully follows the conventions."
    else
        echo "Done: required checks passed, warnings: $WARNINGS."
    fi
    exit 0
else
    echo "Failed: errors: $ERRORS, warnings: $WARNINGS."
    exit 1
fi
