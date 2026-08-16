#!/usr/bin/env sh
set -eu

usage() {
    cat <<EOF
Usage: $(basename "$0") [FLAGS] <owner/repository> [binary-name] [version]
   or: $(basename "$0") -F <archive.tar.gz> [binary-name]

Downloads and installs a program from GitHub Releases.

  -i               pick the version interactively from a list
  -l, --list       print the available versions and exit
  -u, --update     install only if the available version is newer than the current one
  -D, --download   only download the archive + SHA256SUMS and verify the checksum;
                   print the archive path; files are saved into the current directory
  -F, --from-file  install from a local archive (verifying the SHA256SUMS next to it);
                   ignores version, -i, -u; the binary name is taken from the file name
  --user-only      install into ~/.local/bin (no sudo); default is /usr/local/bin
  -h, --help       show this help

  <owner/repository>  e.g.: owner/repo
  [binary-name]       name of the executable (default: repository name)
  [version]           semver like 1.2.3 or v1.2.3 (default: latest)

Environment variables:
  GITHUB_TOKEN    GitHub token: lifts the 60 req/h limit and allows
                  installing from private repositories
EOF
}

INTERACTIVE=0
LIST_ONLY=0
UPDATE_ONLY=0
DOWNLOAD_ONLY=0
USER_ONLY=0
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
        --user-only) USER_ONLY=1; shift ;;
        -F|--from-file)
            if [ $# -lt 2 ]; then
                echo "Flag --from-file requires an argument" >&2; exit 1
            fi
            FROM_FILE="$2"; shift 2 ;;
        --from-file=*) FROM_FILE="${1#--from-file=}"; shift ;;
        -*) echo "Unknown flag: $1" >&2; usage >&2; exit 1 ;;
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
    echo "curl is required" >&2; exit 1
fi

case "$(uname -s)" in
    Linux)  OS=linux ;;
    Darwin) OS=darwin ;;
    *) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
    x86_64|amd64)   ARCH=amd64 ;;
    aarch64|arm64)  ARCH=arm64 ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# --- argument validation ---

if [ -n "$FROM_FILE" ]; then
    if [ ! -f "$FROM_FILE" ]; then
        echo "File not found: $FROM_FILE" >&2; exit 1
    fi
    # the first positional (REPO) without '/' is treated as the binary name
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
            echo "Failed to determine the binary name from the file name: $(basename "$FROM_FILE")" >&2
            echo "Specify the name explicitly: $(basename "$0") -F $FROM_FILE <binary-name>" >&2
            exit 1
        fi
    fi
else
    if [ -z "$REPO" ]; then
        echo "Error: specify owner/repository" >&2
        usage >&2; exit 1
    fi
    case "$REPO" in
        */*)  ;;
        *) echo "Error: the format must be owner/repository (e.g. dimkarp93/envs)" >&2; exit 1 ;;
    esac
fi

# --- helpers ---

api_get() {
    _url="$1"
    _out=$(mktemp)
    _http=$(curl -o "$_out" -w "%{http_code}" -sSL \
        ${GITHUB_TOKEN:+-H "Authorization: token $GITHUB_TOKEN"} \
        "$_url" 2>/dev/null) || true
    if [ "$_http" != "200" ]; then
        cat "$_out" >&2 2>/dev/null || true
        rm -f "$_out"
        echo "GitHub API returned HTTP $_http for $_url" >&2
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
            echo "SHA256 verification failed - the archive is corrupted or tampered with" >&2; return 1
        }
    elif command -v shasum >/dev/null 2>&1; then
        _expected=$(grep " ${_name}$" "$_sums" | awk '{print $1}')
        _actual=$(shasum -a 256 "$_archive" | awk '{print $1}')
        if [ "$_expected" != "$_actual" ]; then
            echo "SHA256 verification failed - the archive is corrupted or tampered with" >&2; return 1
        fi
    else
        echo "Warning: sha256sum/shasum not found, integrity check skipped" >&2
    fi
    echo "Checksum matches"
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

# Extracts the asset API URL (https://api.github.com/.../releases/assets/<id>)
# by asset name from the release JSON. Needed for private repositories: the
# browser_download_url link (github.com/.../releases/download/...) does not
# accept the token and returns 404, while the API endpoint with
# Accept: application/octet-stream does. This relies on GitHub returning one
# field per line, with the asset "url" field preceding its "name".
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
    $SUDO install -m 0755 "$_bin_path" "$TARGET"

    echo "Installed: $TARGET${_bin_ver:+ (version $_bin_ver)}"

    case ":${PATH:-}:" in
        *":$TARGET_DIR:"*) ;;
        *)
            echo
            echo "Warning: $TARGET_DIR is not in PATH."
            echo "Add this line to ~/.profile or ~/.bashrc / ~/.zshrc:"
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
        echo "Executable '$BIN' not found in the archive" >&2; return 1
    fi
}

# --- mode: list versions only ---

if [ "$LIST_ONLY" = "1" ]; then
    VERSIONS=$(list_versions) || exit 1
    if [ -z "$VERSIONS" ]; then
        echo "Repository ${REPO} has no releases" >&2; exit 1
    fi
    echo "$VERSIONS"
    exit 0
fi

# --- mode: install from a local archive ---

if [ -n "$FROM_FILE" ]; then
    ARCHIVE_PATH=$(cd "$(dirname "$FROM_FILE")" && pwd)/$(basename "$FROM_FILE")
    SUMS_PATH="$(dirname "$ARCHIVE_PATH")/SHA256SUMS"

    if [ ! -f "$SUMS_PATH" ]; then
        echo "No SHA256SUMS found next to the archive: $SUMS_PATH" >&2; exit 1
    fi

    echo "Verifying the checksum of $ARCHIVE_PATH"
    check_sha256 "$ARCHIVE_PATH" "$SUMS_PATH" || exit 1

    WORKDIR=$(mktemp -d)
    trap 'rm -rf "$WORKDIR"' EXIT

    echo "Extracting"
    BIN_PATH=$(extract_bin "$ARCHIVE_PATH" "$WORKDIR") || exit 1
    chmod +x "$BIN_PATH"

    BIN_VER=$("$BIN_PATH" --version 2>/dev/null || true)
    do_install "$BIN_PATH" "$BIN_VER"
    exit 0
fi

# --- tag resolution (network modes) ---

RELEASE_JSON=""

if [ "$INTERACTIVE" = "1" ]; then
    VERSIONS=$(list_versions)
    if [ -z "$VERSIONS" ]; then
        echo "Failed to fetch the version list" >&2; exit 1
    fi
    echo "Available versions:"
    i=1
    echo "$VERSIONS" | while IFS= read -r v; do
        printf "  %2d) %s\n" "$i" "$v"
        i=$((i + 1))
    done
    printf "Enter a number or a version: "
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
                echo "Invalid number: $CHOICE" >&2; exit 1
            fi ;;
    esac
elif [ -z "$VERSION" ]; then
    RELEASE_JSON=$(get_release) || exit 1
    TAG=$(echo "$RELEASE_JSON" | grep '"tag_name":' | head -1 \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
    if [ -z "$TAG" ]; then
        echo "Failed to determine the latest version" >&2; exit 1
    fi
else
    case "$VERSION" in
        v*) TAG="$VERSION" ;;
        *)  TAG="v$VERSION" ;;
    esac
fi

# --- auto-detect the binary name from the release assets ---

if [ -z "$BIN" ]; then
    if [ -z "$RELEASE_JSON" ]; then
        RELEASE_JSON=$(get_release "$TAG") || exit 1
    fi
    BIN=$(discover_bin "$RELEASE_JSON")
    if [ -z "$BIN" ]; then
        echo "No asset *-${OS}-${ARCH}.tar.gz found in release ${TAG}" >&2
        echo "Specify the binary name explicitly: $(basename "$0") $REPO <binary-name>" >&2
        exit 1
    fi
fi

ARCHIVE="${BIN}-${OS}-${ARCH}.tar.gz"

# For private repositories the direct browser_download_url does not accept the
# token, so we download via the API asset endpoint. Public ones keep the plain link.
if [ -n "${GITHUB_TOKEN:-}" ]; then
    if [ -z "$RELEASE_JSON" ]; then
        RELEASE_JSON=$(get_release "$TAG") || exit 1
    fi
    ARCHIVE_URL=$(asset_api_url "$ARCHIVE")
    SUMS_URL=$(asset_api_url "SHA256SUMS")
    if [ -z "$ARCHIVE_URL" ]; then
        echo "Asset $ARCHIVE not found in release ${TAG}" >&2; exit 1
    fi
    if [ -z "$SUMS_URL" ]; then
        echo "Asset SHA256SUMS not found in release ${TAG}" >&2; exit 1
    fi
else
    ARCHIVE_URL="https://github.com/${REPO}/releases/download/${TAG}/${ARCHIVE}"
    SUMS_URL="https://github.com/${REPO}/releases/download/${TAG}/SHA256SUMS"
fi

# --- mode: download only ---

if [ "$DOWNLOAD_ONLY" = "1" ]; then
    DEST_DIR="$(pwd)"
    mkdir -p "$DEST_DIR"

    echo "Downloading $ARCHIVE_URL"
    if ! download_file "$ARCHIVE_URL" "$DEST_DIR/$ARCHIVE" 1; then
        echo "Failed to download the archive" >&2; exit 1
    fi

    echo "Downloading SHA256SUMS"
    if ! download_file "$SUMS_URL" "$DEST_DIR/SHA256SUMS"; then
        echo "Failed to download SHA256SUMS" >&2; exit 1
    fi

    check_sha256 "$DEST_DIR/$ARCHIVE" "$DEST_DIR/SHA256SUMS" || {
        rm -f "$DEST_DIR/$ARCHIVE" "$DEST_DIR/SHA256SUMS"
        exit 1
    }

    # the only stdout output is the archive path (everything else went to stderr)
    DEST_ABS=$(cd "$DEST_DIR" && pwd)/$ARCHIVE
    echo "$DEST_ABS"
    exit 0
fi

# --- mode: full install ---

if [ "$UPDATE_ONLY" = "1" ]; then
    CURRENT=""
    if command -v "$BIN" >/dev/null 2>&1; then
        CURRENT=$("$BIN" --version 2>/dev/null || true)
    fi
    LATEST_VER="${TAG#v}"
    if [ "$CURRENT" = "$LATEST_VER" ]; then
        echo "$BIN is already up to date (version $CURRENT)"
        exit 0
    fi
    echo "Updating $BIN: $CURRENT -> $LATEST_VER"
fi

TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

echo "Downloading $ARCHIVE_URL"
if ! download_file "$ARCHIVE_URL" "$TMPDIR/$ARCHIVE" 1; then
    echo "Failed to download the archive" >&2; exit 1
fi

echo "Downloading SHA256SUMS"
if ! download_file "$SUMS_URL" "$TMPDIR/SHA256SUMS"; then
    echo "Failed to download SHA256SUMS" >&2; exit 1
fi

echo "Verifying the checksum"
check_sha256 "$TMPDIR/$ARCHIVE" "$TMPDIR/SHA256SUMS" || exit 1

echo "Extracting"
BIN_PATH=$(extract_bin "$TMPDIR/$ARCHIVE" "$TMPDIR") || exit 1
chmod +x "$BIN_PATH"

EXPECTED_VER="${TAG#v}"
ACTUAL_VER=$("$BIN_PATH" --version 2>/dev/null || true)
if [ -n "$ACTUAL_VER" ] && [ "$ACTUAL_VER" != "$EXPECTED_VER" ]; then
    echo "Warning: the binary version ($ACTUAL_VER) does not match the tag ($EXPECTED_VER)" >&2
fi

do_install "$BIN_PATH" "${ACTUAL_VER:-$EXPECTED_VER}"
