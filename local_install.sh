#!/usr/bin/env sh
set -eu

usage() {
    cat <<EOF
Usage: $(basename "$0") [FLAGS] [path]

Builds a program from a local git repository and installs the binary.

  --user-only   install into ~/.local/bin (no sudo); default is /usr/local/bin
  -h, --help    show this help

  [path]  absolute path to the repository, or a relative one - looked up in
          the roots from ~/.config/install/roots.txt (default: ~/tools).
          If no path is given, the current directory is used.

Repository requirements:
  - contains .git
  - contains versions.txt with semver X.Y.Z
  - the binary name matches the directory name
  - has a 'just build' (Justfile) or 'make build' (Makefile) target
    that puts the binary <name> into the repository root
EOF
}

PROGRAM_PATH=""
USER_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --user-only) USER_ONLY=1; shift ;;
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

# no path given - use the current directory
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

# --- path resolution ---

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

# --- validation ---

if [ ! -d "$REPO_DIR" ]; then
    echo "Error: path is not a directory: $REPO_DIR" >&2; exit 1
fi

if [ ! -d "$REPO_DIR/.git" ]; then
    echo "Error: $REPO_DIR is not a git repository (no .git)" >&2; exit 1
fi

if [ ! -f "$REPO_DIR/versions.txt" ]; then
    echo "Error: $REPO_DIR/versions.txt not found" >&2; exit 1
fi

# normalize the directory path (so basename gives the correct binary name)
REPO_DIR=$(cd "$REPO_DIR" && pwd)

# --- version from versions.txt ---

VERSION=$(tr -d '[:space:]' < "$REPO_DIR/versions.txt")
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Error: versions.txt must contain semver X.Y.Z (got: '$VERSION')" >&2; exit 1
fi

# --- binary name ---

BIN=$(basename "$REPO_DIR")

echo "Repository:  $REPO_DIR"
echo "Binary:      $BIN"
echo "Version:     $VERSION"

# --- build ---

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
    echo "Error: neither Justfile nor Makefile found in $REPO_DIR" >&2
    echo "The repository must provide a 'just build' or 'make build' target" >&2
    exit 1
fi

echo "Building: $BUILD_CMD (in $REPO_DIR)"
(cd "$REPO_DIR" && $BUILD_CMD)

# --- check the built binary ---

BIN_PATH="$REPO_DIR/$BIN"
if [ ! -x "$BIN_PATH" ]; then
    echo "Error: binary '$BIN' not found in the repository root after the build: $BIN_PATH" >&2
    echo "The build target must put the executable '$BIN' into the repository root" >&2
    exit 1
fi

# --- install ---

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
        echo "Directory $TARGET_DIR is not writable and sudo was not found." >&2; exit 1
    fi
fi

$SUDO mkdir -p "$TARGET_DIR"
$SUDO install -m 0755 "$BIN_PATH" "$TARGET"

echo "Installed: $TARGET (version $VERSION)"

case ":${PATH:-}:" in
    *":$TARGET_DIR:"*) ;;
    *)
        echo
        echo "Warning: $TARGET_DIR is not in PATH."
        echo "Add this line to ~/.profile or ~/.bashrc / ~/.zshrc:"
        echo "    export PATH=\"$TARGET_DIR:\$PATH\""
        ;;
esac
