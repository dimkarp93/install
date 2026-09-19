#!/usr/bin/env sh
set -eu

usage() {
    cat <<EOF
Usage: $(basename "$0") [FLAGS] [path]

Checks whether a repository follows the conventions from CONVENTIONS.md.

  --build       additionally build the binary and check its --version output
  --fix         create the missing files and recipes before checking
                (versions.txt, .gitignore, bump-* recipes, release workflow)
  -h, --help    show this help

  [path]  path to the repository: an absolute path, or a name or relative
          path - resolved against the current directory.
          If no path is given, the current directory is used.

Exit code 0 - all required checks passed; 1 - there are errors.
EOF
}

PROGRAM_PATH=""
DO_BUILD=0
DO_FIX=0

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --build) DO_BUILD=1; shift ;;
        --fix) DO_FIX=1; shift ;;
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

normalize_git_url() {
    case "$1" in
        "")
            printf 'local' ;;
        *://*)
            _h=${1#*://}
            _h=${_h#*@}
            printf 'https://%s' "${_h%.git}" ;;
        *:*)
            _h=${1#*@}
            printf 'https://%s' "$(printf '%s' "${_h%.git}" | tr ':' '/')" ;;
        *)
            printf 'local' ;;
    esac
}

ERRORS=0
WARNINGS=0
ok()   { printf '  [OK]   %s\n'   "$1"; }
warn() { printf '  [WARN] %s\n'   "$1"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf '  [FAIL] %s\n'   "$1"; ERRORS=$((ERRORS + 1)); }
fixed(){ printf '  [FIX]  %s\n'   "$1"; }

semver_le() {
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$1" ]
}

# --- path resolution ---

PROGRAM_PATH=$(expand_tilde "$PROGRAM_PATH")

case "$PROGRAM_PATH" in
    /*) REPO_DIR="$PROGRAM_PATH" ;;
    *)  REPO_DIR="$PWD/$PROGRAM_PATH" ;;
esac

if [ ! -d "$REPO_DIR" ]; then
    echo "Error: path is not a directory: $REPO_DIR" >&2; exit 1
fi
REPO_DIR=$(cd "$REPO_DIR" && pwd)

BIN=$(basename "$REPO_DIR")

if [ -f "$REPO_DIR/go.mod" ]; then
    REPO_LANG=go
else
    REPO_LANG=sh
fi

if [ "$DO_FIX" = "1" ]; then
    INITER=""
    _self_dir=$(cd "$(dirname "$0")" && pwd)
    if [ -x "$_self_dir/init_install.sh" ]; then
        INITER="$_self_dir/init_install.sh"
    elif command -v init_install.sh >/dev/null 2>&1; then
        INITER="init_install.sh"
    fi
    if [ -z "$INITER" ]; then
        echo "Error: --fix needs init_install.sh (the source of the templates) in PATH or next to this script" >&2
        exit 1
    fi

    echo "Fixing: $REPO_DIR"

    if [ ! -f "$REPO_DIR/versions.txt" ]; then
        printf '0.1.0\n' > "$REPO_DIR/versions.txt"
        fixed "created versions.txt = 0.1.0"
    fi

    _gi="$REPO_DIR/.gitignore"
    if [ ! -f "$_gi" ]; then
        "$INITER" --emit "gitignore-$REPO_LANG" | sed "s|__NAME__|$BIN|g" > "$_gi"
        fixed "created .gitignore"
    else
        for _entry in "/$BIN" "/dist/"; do
            if ! grep -Fxq "$_entry" "$_gi"; then
                [ -n "$(tail -c1 "$_gi")" ] && printf '\n' >> "$_gi"
                printf '%s\n' "$_entry" >> "$_gi"
                fixed "added $_entry to .gitignore"
            fi
        done
    fi

    _jf=""
    [ -f "$REPO_DIR/justfile" ] && _jf="$REPO_DIR/justfile"
    [ -z "$_jf" ] && [ -f "$REPO_DIR/Justfile" ] && _jf="$REPO_DIR/Justfile"
    if [ -n "$_jf" ]; then
        _need=0
        for _r in bump-patch bump-minor bump-major; do
            grep -Eq "^${_r}( |:)" "$_jf" || _need=1
        done
        if [ "$_need" = "1" ]; then
            [ -n "$(tail -c1 "$_jf")" ] && printf '\n' >> "$_jf"
            printf '\n' >> "$_jf"
            "$INITER" --emit bump-recipes >> "$_jf"
            fixed "appended the bump-patch/bump-minor/bump-major recipes to $(basename "$_jf")"
        fi
    elif [ -f "$REPO_DIR/Makefile" ] || [ -f "$REPO_DIR/makefile" ]; then
        _need=0
        _mf="$REPO_DIR/Makefile"; [ -f "$_mf" ] || _mf="$REPO_DIR/makefile"
        for _r in bump-patch bump-minor bump-major; do
            grep -Eq "^${_r}( |:)" "$_mf" || _need=1
        done
        if [ "$_need" = "1" ]; then
            fixed "Makefile is not edited automatically - add the bump-* targets by hand (see CONVENTIONS.md)"
        fi
    fi

    _wf_any=0
    for _f in "$REPO_DIR"/.github/workflows/*.yml "$REPO_DIR"/.github/workflows/*.yaml \
              "$REPO_DIR"/.gitea/workflows/*.yml "$REPO_DIR"/.gitea/workflows/*.yaml; do
        [ -f "$_f" ] && _wf_any=1
    done
    if [ "$_wf_any" = "0" ]; then
        mkdir -p "$REPO_DIR/.github/workflows"
        "$INITER" --emit "workflow-${REPO_LANG}-github" > "$REPO_DIR/.github/workflows/release.yml"
        fixed "created .github/workflows/release.yml (${REPO_LANG})"
    fi

    echo
fi

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
ok "binary name from directory name = $BIN"

echo ".gitignore:"
if [ ! -f "$REPO_DIR/.gitignore" ]; then
    warn "no .gitignore - the binary '$BIN' built in the root will be offered for commit"
elif grep -Fxq "/$BIN" "$REPO_DIR/.gitignore" || grep -Fxq "$BIN" "$REPO_DIR/.gitignore"; then
    ok "the binary '$BIN' is ignored"
else
    warn "the binary '$BIN' is not listed in .gitignore"
fi

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
WF_FILES=""
for _f in "$REPO_DIR"/.github/workflows/*.yml "$REPO_DIR"/.github/workflows/*.yaml \
          "$REPO_DIR"/.gitea/workflows/*.yml "$REPO_DIR"/.gitea/workflows/*.yaml; do
    [ -f "$_f" ] || continue
    _wf_found=1
    WF_FILES="$WF_FILES $_f"
done
if [ "$_wf_found" = "1" ]; then
    ok ".github/workflows/*.yml or .gitea/workflows/*.yml found"
    if grep -lq 'SHA256SUMS' $WF_FILES 2>/dev/null; then
        ok "the workflow generates SHA256SUMS"
    else
        warn "no SHA256SUMS in the release workflow - github_install.sh will not be able to verify the archive"
    fi
    if grep -lqE -- '-linux-amd64|linux/amd64' $WF_FILES 2>/dev/null; then
        ok "the workflow builds archives for the platforms from the conventions"
    else
        warn "the release workflow does not look like the template from this repository (no per-platform archives)"
    fi
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
    if [ -n "$VERSION" ]; then
        _latest=$(cd "$REPO_DIR" && git tag 2>/dev/null \
            | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' \
            | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
        if [ -n "$_latest" ] && [ "$_latest" = "$VERSION" ]; then
            warn "tag v$VERSION already exists - bump versions.txt, otherwise the workflow will skip the release"
        elif [ -n "$_latest" ] && semver_le "$VERSION" "$_latest"; then
            warn "versions.txt ($VERSION) is below the latest tag (v$_latest)"
        elif [ -n "$_latest" ]; then
            ok "versions.txt ($VERSION) is above the latest tag (v$_latest)"
        fi
    fi
else
    warn "git is unavailable - tags were not checked"
fi

# --- origin ---

echo "Origin:"
if [ -f "$REPO_DIR/upstream.txt" ]; then
    UPSTREAM=$(tr -d '[:space:]' < "$REPO_DIR/upstream.txt")
    if printf '%s' "$UPSTREAM" | grep -Eq '^https://[^[:space:]@]+$'; then
        ok "upstream.txt = $UPSTREAM"
    else
        fail "upstream.txt must contain one canonical https URL (got: '$UPSTREAM')"
    fi
else
    ok "no upstream.txt - upstream equals origin"
fi

if [ -n "$BUILD_FILE" ]; then
    if grep -Eq 'main\.origin|ORIGIN=' "$BUILD_FILE" 2>/dev/null; then
        ok "the origin is embedded by $(basename "$BUILD_FILE")"
    else
        warn "$(basename "$BUILD_FILE") does not embed the origin - a local build will have no origin"
    fi
fi

if [ "$_wf_found" = "1" ]; then
    if grep -lqE 'main\.origin|ORIGIN=' $WF_FILES 2>/dev/null; then
        ok "the origin is embedded by the release workflow"
    else
        warn "the release workflow does not embed the origin - released binaries will have no origin"
    fi
fi

_leak_files="$WF_FILES"
[ -n "$BUILD_FILE" ] && _leak_files="$_leak_files $BUILD_FILE"
if [ -n "$_leak_files" ] \
   && grep -Eq 'main\.origin=[^ "]*\$[({]?(shell +)?git remote get-url' $_leak_files 2>/dev/null; then
    warn "'git remote get-url' is embedded into main.origin directly - normalise the URL first (see CONVENTIONS.md), otherwise credentials may leak into the binary"
fi

# --- go install requirements (optional section of the conventions) ---

if [ -f "$REPO_DIR/go.mod" ]; then
    echo "Go (go install):"
    MOD=$(awk '/^module /{print $2; exit}' "$REPO_DIR/go.mod")
    if [ -z "$MOD" ]; then
        warn "no module directive in go.mod"
    else
        MOD_BASE=$(printf '%s' "$MOD" | sed -E 's|/v[0-9]+$||')
        case "$MOD_BASE" in
            */*/*)
                case "${MOD_BASE%%/*}" in
                    *.*) ok "module path is a network address: $MOD" ;;
                    *)   warn "module path '$MOD' has no host - go install is impossible" ;;
                esac ;;
            *) warn "module path '$MOD' has no host - go install is impossible" ;;
        esac
        if [ "${MOD_BASE##*/}" != "$BIN" ]; then
            warn "the last segment of the module path ('${MOD_BASE##*/}') differs from the binary name ('$BIN')"
        else
            ok "the last segment of the module path matches the binary name"
        fi
        if [ -n "$VERSION" ]; then
            _maj=${VERSION%%.*}
            if [ "$_maj" -ge 2 ] 2>/dev/null; then
                case "$MOD" in
                    */v"$_maj") ok "the module path carries the /v$_maj major suffix" ;;
                    *) warn "versions.txt = $VERSION, but the module path has no /v$_maj suffix - go install will fail" ;;
                esac
            fi
        fi
    fi
    if grep -Eq '^[[:space:]]*replace[[:space:]]' "$REPO_DIR/go.mod"; then
        warn "go.mod has a replace directive - go install does not support it (keep local replaces in go.work)"
    else
        ok "no replace directives in go.mod"
    fi
    if [ -d "$REPO_DIR/cmd/$BIN" ] && grep -rlq '^package main' "$REPO_DIR/cmd/$BIN" 2>/dev/null; then
        ok "package main in cmd/$BIN/"
    elif grep -lq '^package main' "$REPO_DIR"/*.go 2>/dev/null; then
        warn "package main lives in the module root - go install works, but the library code cannot be imported separately (cmd/$BIN/ is recommended)"
    else
        warn "no package main in cmd/$BIN/ and none in the module root"
    fi
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
            elif [ "$(printf '%s\n' "$_ver" | wc -l)" -gt 1 ]; then
                fail "--version must print exactly one line (got $(printf '%s\n' "$_ver" | wc -l))"
            elif [ -n "$VERSION" ] && [ "$_ver" != "$VERSION" ]; then
                fail "--version printed '$_ver', expected '$VERSION' (from versions.txt)"
            else
                ok "--version = $_ver"
            fi

            _org=$("$BIN_PATH" --origin 2>/dev/null || true)
            if [ -z "$_org" ]; then
                fail "--origin printed nothing"
            elif [ "$(printf '%s\n' "$_org" | wc -l)" -gt 1 ]; then
                fail "--origin must print exactly one line (got $(printf '%s\n' "$_org" | wc -l))"
            elif printf '%s' "$_org" | grep -q '@'; then
                fail "--origin contains credentials or an ssh user: '$_org' (see CONVENTIONS.md)"
            elif ! printf '%s' "$_org" | grep -Eq '^(https://[^[:space:]]+|local)$'; then
                fail "--origin must be a canonical https URL or 'local' (got: '$_org')"
            elif printf '%s' "$_org" | grep -Eq '\.git$|/$'; then
                fail "--origin must have no .git suffix and no trailing slash (got: '$_org')"
            else
                ok "--origin = $_org"
                _remote=$(cd "$REPO_DIR" && git remote get-url origin 2>/dev/null || true)
                _remote=$(normalize_git_url "$_remote")
                if [ "$_remote" != "local" ] && [ "$_org" != "$_remote" ]; then
                    warn "--origin ('$_org') differs from the repository remote ('$_remote')"
                fi
            fi

            _bi=$("$BIN_PATH" --buildinfo 2>/dev/null || true)
            if [ -z "$_bi" ] || ! printf '%s\n' "$_bi" | grep -Eq '^[a-z]+='; then
                warn "--buildinfo is not supported"
            else
                _bi_ver=$(printf '%s\n' "$_bi" | sed -n 's/^version=//p' | head -1)
                if ! printf '%s\n' "$_bi" | grep -q '^origin='; then
                    fail "--buildinfo has no 'origin=' line"
                elif [ -z "$_bi_ver" ]; then
                    fail "--buildinfo has no 'version=' line"
                elif [ -n "$VERSION" ] && [ "$_bi_ver" != "$VERSION" ]; then
                    fail "--buildinfo version=$_bi_ver, expected '$VERSION' (from versions.txt)"
                elif ! printf '%s\n' "$_bi" | grep -q '^upstream='; then
                    fail "--buildinfo has no 'upstream=' line"
                else
                    ok "--buildinfo reports origin, upstream and version=$_bi_ver"
                    _bi_ch=$(printf '%s\n' "$_bi" | sed -n 's/^channel=//p' | head -1)
                    if [ -z "$_bi_ch" ]; then
                        warn "--buildinfo has no 'channel=' line"
                    elif [ "$_bi_ch" != "local" ]; then
                        warn "a local build reports channel=$_bi_ch, expected 'local'"
                    else
                        ok "--buildinfo channel=local"
                    fi
                fi
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
