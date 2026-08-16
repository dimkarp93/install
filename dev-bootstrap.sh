#!/usr/bin/env sh
set -eu

# dev counterpart of bootstrap.sh: installs the installers from the current
# working copy of this repository (next to this script) instead of GitHub.
# Handy while editing the installers: edit -> dev-bootstrap.sh -> check in PATH.

SCRIPTS="github_install.sh gitea_install.sh local_install.sh go_install.sh check_install.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [FLAGS]

Copies the installers (${SCRIPTS}) from the current working copy into PATH.

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

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# make sure the sources are present
for _name in $SCRIPTS; do
    if [ ! -f "$SCRIPT_DIR/$_name" ]; then
        echo "Not found: $SCRIPT_DIR/$_name - run dev-bootstrap.sh from the install working copy" >&2
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
        echo "Directory $TARGET_DIR is not writable and sudo was not found." >&2; exit 1
    fi
fi

$SUDO mkdir -p "$TARGET_DIR"

for _name in $SCRIPTS; do
    $SUDO install -m 0755 "$SCRIPT_DIR/$_name" "$TARGET_DIR/$_name"
    echo "Installed: $TARGET_DIR/$_name (from $SCRIPT_DIR/$_name)"
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
