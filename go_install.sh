#!/usr/bin/env sh
set -eu

usage() {
    cat <<EOF
Usage: $(basename "$0") [FLAGS] <module-path> [version]

Installs a Go program via 'go install' and puts the binary into PATH.

  -l, --list       print the available module versions and exit
  -p, --pkg PATH   package path inside the module (detected automatically
                   by default: <module>/cmd/<name>, then <module>)
  --gobin          keep the binary in GOBIN (~/go/bin), do not copy it into PATH
  --user-only      install into ~/.local/bin (no sudo); default is /usr/local/bin
  -h, --help       show this help

  <module-path>  module path, e.g.: github.com/dimkarp93/md-pdf
  [version]      semver like 1.2.3 or v1.2.3 (default: latest)

Requires an installed Go toolchain. The module must follow the Go conventions from
CONVENTIONS.md: network module path, published dependencies, no replace in go.mod.
If Go is missing or the program is not written in Go, use github_install.sh or
gitea_install.sh.

Flags -D, -F, -i, -u are not supported: 'go install' has no intermediate archive.
Use github_install.sh / gitea_install.sh for those scenarios.

  GOPRIVATE  for private repositories, e.g.: GOPRIVATE=github.com/dimkarp93/*
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
                echo "Flag --pkg requires an argument" >&2; exit 1
            fi
            PKG="$2"; shift 2 ;;
        --pkg=*) PKG="${1#--pkg=}"; shift ;;
        -*) echo "Unknown flag: $1" >&2; usage >&2; exit 1 ;;
        *)
            if [ -z "$MODULE" ]; then
                MODULE="$1"
            elif [ -z "$VERSION_ARG" ]; then
                VERSION_ARG="$1"
            else
                echo "Error: unexpected extra argument: $1" >&2; usage >&2; exit 1
            fi
            shift ;;
    esac
done

if [ -z "$MODULE" ]; then
    echo "Error: module-path is not specified" >&2; usage >&2; exit 1
fi

MODULE=${MODULE%/}

if ! command -v go >/dev/null 2>&1; then
    echo "Error: 'go' not found in PATH - go_install.sh requires an installed Go toolchain." >&2
    echo "Install Go (https://go.dev/dl/) or use github_install.sh /" >&2
    echo "gitea_install.sh - they install a prebuilt binary and do not require Go." >&2
    exit 1
fi

case "$MODULE" in
    */*) ;;
    *)
        echo "Error: '$MODULE' does not look like a module-path." >&2
        echo "A network path like github.com/owner/repo is expected (see CONVENTIONS.md)." >&2
        exit 1 ;;
esac

private_hint() {
    if [ -z "${GOPRIVATE:-}" ]; then
        echo "If the repository is private, set GOPRIVATE, e.g.:" >&2
        echo "    GOPRIVATE=$(printf '%s' "$MODULE" | cut -d/ -f1-2)/* $(basename "$0") $MODULE" >&2
        echo "and configure git access to the repository (SSH key or ~/.netrc)." >&2
    else
        echo "GOPRIVATE=$GOPRIVATE is set - check git access to the repository" >&2
        echo "(SSH key, ~/.netrc or git config url.<...>.insteadOf)." >&2
    fi
}

if [ "$LIST_ONLY" = "1" ]; then
    _versions=$(go list -m -versions "$MODULE" 2>/dev/null) || {
        echo "Failed to fetch the version list for module $MODULE" >&2
        private_hint
        exit 1
    }
    _versions=$(printf '%s' "$_versions" | cut -s -d' ' -f2-)
    if [ -z "$_versions" ]; then
        echo "Module $MODULE has no published versions (no semver tags)" >&2
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
        echo "Error: version must be semver X.Y.Z or vX.Y.Z (got: '$VERSION_ARG')" >&2
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

echo "Module:       $MODULE"
echo "Version:      $VERSION"

INSTALL_LOG=$(mktemp)
trap 'rm -rf "$GOBIN_TMP"; rm -f "$INSTALL_LOG"' EXIT

INSTALLED_PKG=""
for _pkg in $CANDIDATES; do
    echo "Trying:       go install $_pkg@$VERSION"
    if GOBIN="$GOBIN_TMP" go install -trimpath "$_pkg@$VERSION" >"$INSTALL_LOG" 2>&1; then
        INSTALLED_PKG="$_pkg"
        break
    fi
done

if [ -z "$INSTALLED_PKG" ]; then
    echo "Error: failed to install $MODULE@$VERSION" >&2
    cat "$INSTALL_LOG" >&2
    if grep -qiE '404|not found|unrecognized import|terminal prompts disabled|authentication' "$INSTALL_LOG"; then
        private_hint
    fi
    exit 1
fi

BUILT=$(find "$GOBIN_TMP" -maxdepth 1 -type f | head -1)
if [ -z "$BUILT" ]; then
    echo "Error: go install succeeded but no binary was found in $GOBIN_TMP" >&2
    exit 1
fi

BIN=$(basename "$BUILT")

ACTUAL_VERSION=$(go version -m "$BUILT" 2>/dev/null \
    | awk '$1 == "mod" { print $3; exit }')
[ -n "$ACTUAL_VERSION" ] || ACTUAL_VERSION="$VERSION"

echo "Package:      $INSTALLED_PKG"
echo "Binary:       $BIN"

if [ "$KEEP_GOBIN" = "1" ]; then
    TARGET_DIR=$(go env GOBIN)
    if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$(go env GOPATH)/bin"
    fi
    mkdir -p "$TARGET_DIR"
    install -m 0755 "$BUILT" "$TARGET_DIR/$BIN"
    echo "Installed: $TARGET_DIR/$BIN (version $ACTUAL_VERSION)"
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
            echo "Directory $TARGET_DIR is not writable and sudo was not found." >&2; exit 1
        fi
    fi

    $SUDO mkdir -p "$TARGET_DIR"
    $SUDO install -m 0755 "$BUILT" "$TARGET_DIR/$BIN"
    echo "Installed: $TARGET_DIR/$BIN (version $ACTUAL_VERSION)"
fi

case ":${PATH:-}:" in
    *":$TARGET_DIR:"*) ;;
    *)
        echo
        echo "Warning: $TARGET_DIR is not in PATH."
        echo "Add this line to ~/.profile or ~/.bashrc / ~/.zshrc:"
        echo "    export PATH=\"$TARGET_DIR:\$PATH\""
        ;;
esac
