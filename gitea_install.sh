#!/usr/bin/env sh
set -eu

usage() {
    cat <<EOF
Usage: $(basename "$0") -s <gitea-host> [FLAGS] <owner/repository> [binary-name] [version]
   or: $(basename "$0") -F <archive.tar.gz> [binary-name]

Downloads and installs a program from Gitea Releases.

  -s, --server     Gitea instance address, e.g. https://git.example.com
                   (the scheme may be omitted: git.example.com becomes https://);
                   if not given, taken from the GITEA_URL environment variable
  -i               pick the version interactively from a list
  -l, --list       print the available versions and exit
  -u, --update     install only if the available version is newer than the current one
  -D, --download   only download the archive + SHA256SUMS and verify the checksum;
                   print the archive path; files are saved into the current directory
  -F, --from-file  install from a local archive (verifying the SHA256SUMS next to it);
                   ignores version, -i, -u, -s; the binary name is taken from the file name
  --user-only      install into ~/.local/bin (no sudo); default is /usr/local/bin
  -h, --help       show this help

  <owner/repository>  e.g.: owner/repo
  [binary-name]       name of the executable (default: repository name)
  [version]           semver like 1.2.3 or v1.2.3 (default: latest)

Environment variables:
  GITEA_URL       Gitea instance address (alternative to the -s flag)
  GITEA_TOKEN     Gitea token with the read:repository scope: required to install
                  from private repositories
EOF
}

INTERACTIVE=0
LIST_ONLY=0
UPDATE_ONLY=0
DOWNLOAD_ONLY=0
USER_ONLY=0
FROM_FILE=""
SERVER="${GITEA_URL:-}"
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
        -s|--server)
            if [ $# -lt 2 ]; then
                echo "Flag --server requires an argument" >&2; exit 1
            fi
            SERVER="$2"; shift 2 ;;
        --server=*) SERVER="${1#--server=}"; shift ;;
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

if [ -n "$FROM_FILE" ]; then
    if [ ! -f "$FROM_FILE" ]; then
        echo "File not found: $FROM_FILE" >&2; exit 1
    fi
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
    if [ -z "$SERVER" ]; then
        echo "Error: specify the Gitea host with the -s flag or the GITEA_URL environment variable" >&2
        echo "For example: $(basename "$0") -s https://git.example.com owner/repo" >&2
        usage >&2; exit 1
    fi
    case "$SERVER" in
        http://*|https://*) ;;
        *) SERVER="https://$SERVER" ;;
    esac
    while :; do
        case "$SERVER" in
            */) SERVER="${SERVER%/}" ;;
            *) break ;;
        esac
    done

    if [ -z "$REPO" ]; then
        echo "Error: specify owner/repository" >&2
        usage >&2; exit 1
    fi
    case "$REPO" in
        */*)  ;;
        *) echo "Error: the format must be owner/repository (e.g. dimkarp93/envs)" >&2; exit 1 ;;
    esac
fi

api_get() {
    _url="$1"
    _quiet="${2:-0}"
    _out=$(mktemp)
    if [ -n "${GITEA_TOKEN:-}" ]; then
        _http=$(curl -o "$_out" -w "%{http_code}" -sSL \
            -H "Authorization: token $GITEA_TOKEN" "$_url" 2>/dev/null) || true
    else
        _http=$(curl -o "$_out" -w "%{http_code}" -sSL "$_url" 2>/dev/null) || true
    fi
    if [ "$_http" != "200" ]; then
        rm -f "$_out"
        if [ "$_quiet" != "1" ]; then
            echo "Gitea API returned HTTP $_http for $_url" >&2
            if [ "$_http" = "401" ] || [ "$_http" = "403" ] || [ "$_http" = "404" ]; then
                if [ -z "${GITEA_TOKEN:-}" ]; then
                    echo "If the repository is private, set GITEA_TOKEN (read:repository scope)" >&2
                else
                    echo "Check that GITEA_TOKEN is valid and has the read:repository scope" >&2
                fi
            fi
        fi
        return 1
    fi
    cat "$_out"
    rm -f "$_out"
}

repo_exists() {
    api_get "${SERVER}/api/v1/repos/${REPO}" 1 >/dev/null 2>&1
}

fail_no_release() {
    if repo_exists; then
        echo "Repository ${REPO} on ${SERVER} has no published releases." >&2
        echo "Check the list: $(basename "$0") -s $SERVER -l $REPO" >&2
        echo "Note: git tags without a created release cannot be installed." >&2
    else
        echo "Repository ${REPO} was not found or is not accessible on ${SERVER}." >&2
        if [ -z "${GITEA_TOKEN:-}" ]; then
            echo "If the repository is private, set GITEA_TOKEN (read:repository scope)" >&2
        else
            echo "Check that GITEA_TOKEN is valid and has the read:repository scope" >&2
        fi
    fi
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
    if [ -n "${GITEA_TOKEN:-}" ]; then
        curl -fL $_progress \
            -H "Authorization: token $GITEA_TOKEN" \
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
    _json=$(api_get "${SERVER}/api/v1/repos/${REPO}/releases?limit=100") || return 1
    echo "$_json" \
        | grep -o '"tag_name":[[:space:]]*"[^"]*"' \
        | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/'
}

get_release() {
    _tag="${1:-}"
    _quiet="${2:-0}"
    if [ -z "$_tag" ]; then
        api_get "${SERVER}/api/v1/repos/${REPO}/releases/latest" "$_quiet"
    else
        api_get "${SERVER}/api/v1/repos/${REPO}/releases/tags/${_tag}" "$_quiet"
    fi
}

discover_bin() {
    echo "$1" \
        | grep -o '"name":[[:space:]]*"[^"]*"' \
        | grep -o "\"[^\"]*-${OS}-${ARCH}\.tar\.gz\"" \
        | tr -d '"' \
        | head -1 \
        | sed -E "s/-${OS}-${ARCH}\\.tar\\.gz\$//"
}

asset_url() {
    printf '%s' "$RELEASE_JSON" \
        | tr -d '\n' \
        | tr '{}' '\n\n' \
        | grep "\"name\":[[:space:]]*\"$1\"" \
        | grep -o '"browser_download_url":[[:space:]]*"[^"]*"' \
        | sed -E 's/.*"browser_download_url":[[:space:]]*"([^"]+)".*/\1/' \
        | head -1
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

if [ "$LIST_ONLY" = "1" ]; then
    VERSIONS=$(list_versions) || exit 1
    if [ -z "$VERSIONS" ]; then
        echo "Repository ${REPO} has no releases" >&2; exit 1
    fi
    echo "$VERSIONS"
    exit 0
fi

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
    if ! RELEASE_JSON=$(get_release "" 1); then
        fail_no_release
        exit 1
    fi
    TAG=$(echo "$RELEASE_JSON" | grep -o '"tag_name":[[:space:]]*"[^"]*"' | head -1 \
        | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/')
    if [ -z "$TAG" ]; then
        echo "Failed to determine the latest version" >&2; exit 1
    fi
else
    case "$VERSION" in
        v*) TAG="$VERSION" ;;
        *)  TAG="v$VERSION" ;;
    esac
fi

if [ -z "$BIN" ]; then
    if [ -z "$RELEASE_JSON" ]; then
        RELEASE_JSON=$(get_release "$TAG") || exit 1
    fi
    BIN=$(discover_bin "$RELEASE_JSON")
    if [ -z "$BIN" ]; then
        echo "No asset *-${OS}-${ARCH}.tar.gz found in release ${TAG}" >&2
        echo "Specify the binary name explicitly: $(basename "$0") -s $SERVER $REPO <binary-name>" >&2
        exit 1
    fi
fi

ARCHIVE="${BIN}-${OS}-${ARCH}.tar.gz"

if [ -z "$RELEASE_JSON" ]; then
    RELEASE_JSON=$(get_release "$TAG") || exit 1
fi

ARCHIVE_URL=$(asset_url "$ARCHIVE")
SUMS_URL=$(asset_url "SHA256SUMS")

if [ -z "$ARCHIVE_URL" ]; then
    echo "Asset $ARCHIVE not found in release ${TAG}" >&2; exit 1
fi
if [ -z "$SUMS_URL" ]; then
    echo "Asset SHA256SUMS not found in release ${TAG}" >&2; exit 1
fi

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

    DEST_ABS=$(cd "$DEST_DIR" && pwd)/$ARCHIVE
    echo "$DEST_ABS"
    exit 0
fi

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
