#!/usr/bin/env sh
set -eu

REPO="dimkarp93/install"
BRANCH="master"
SCRIPTS="github_install.sh gitea_install.sh local_install.sh go_install.sh check_install.sh"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [FLAGS]

Downloads the installers (${SCRIPTS}) and puts them into PATH.

  --user-only   install into ~/.local/bin (no sudo); default is /usr/local/bin
  -h, --help    show this help
EOF
}

USER_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --user-only) USER_ONLY=1; shift ;;
        *) echo "Unknown flag: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required" >&2; exit 1
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
        echo "Directory $TARGET_DIR is not writable and sudo was not found." >&2; exit 1
    fi
fi

$SUDO mkdir -p "$TARGET_DIR"

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

for _name in $SCRIPTS; do
    _url="${BASE_URL}/${_name}"
    echo "Downloading $_url"
    if ! curl -fsSL -o "$TMPFILE" "$_url"; then
        echo "Failed to download $_name" >&2; exit 1
    fi
    $SUDO install -m 0755 "$TMPFILE" "$TARGET_DIR/$_name"
    echo "Installed: $TARGET_DIR/$_name"
done

case ":${PATH:-}:" in
    *":$TARGET_DIR:"*) ;;
    *)
        echo
        echo "Warning: $TARGET_DIR is not in PATH."
        echo "Add this line to ~/.profile or ~/.bashrc / ~/.zshrc:"
        echo "    export PATH=\"$TARGET_DIR:\$PATH\""
        ;;
esac
