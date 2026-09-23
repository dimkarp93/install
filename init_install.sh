#!/usr/bin/env sh
set -eu

usage() {
    cat <<EOF
Usage: $(basename "$0") [FLAGS] <name|path>

Creates a new repository that follows the conventions from CONVENTIONS.md:
versions.txt, a build file with build/bump-*/release recipes, --version /
--origin / --buildinfo flags, .gitignore and a release workflow. Go
programs get their dependencies in vendor/ and are built only from it.

  --lang go|sh          language of the skeleton (default: go)
  --owner OWNER         repository owner (required for --lang go)
  --host HOST           repository host (default: github.com)
  --upstream URL        write upstream.txt with the canonical repository URL
  --ci LIST             which release workflows to add: a comma-separated list of
                        github, gitea, gitlab; or all, none
                        (default: github)
  --remote URL          git remote add origin URL
  --no-git              do not run git init and do not create the first commit
  --force               fill an existing directory (existing files are kept)
  --emit TEMPLATE       print a template to stdout and exit
  -h, --help            show this help

  <name|path>  path to the new repository: an absolute path, or a name or
               relative path - resolved against the current directory.

Templates for --emit: justfile-go, justfile-sh, main-go, source-sh,
gitignore-go, gitignore-sh, readme, bump-recipes, vendor-env,
vendor-recipes, gitattributes-vendor, workflow-go-github, workflow-go-gitea, workflow-go-gitlab,
workflow-sh-github, workflow-sh-gitea, workflow-sh-gitlab.
EOF
}

PROG_LANG="go"
OWNER=""
HOST="github.com"
UPSTREAM_URL=""
CI="github"
REMOTE_URL=""
DO_GIT=1
FORCE=0
EMIT=""
TARGET=""

need_value() {
    [ "$2" -ge 2 ] || { echo "Flag $1 requires a value" >&2; exit 1; }
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --lang)     need_value "$1" $#; PROG_LANG="$2"; shift 2 ;;
        --owner)    need_value "$1" $#; OWNER="$2"; shift 2 ;;
        --host)     need_value "$1" $#; HOST="$2"; shift 2 ;;
        --upstream) need_value "$1" $#; UPSTREAM_URL="$2"; shift 2 ;;
        --ci)       need_value "$1" $#; CI="$2"; shift 2 ;;
        --remote)   need_value "$1" $#; REMOTE_URL="$2"; shift 2 ;;
        --emit)     need_value "$1" $#; EMIT="$2"; shift 2 ;;
        --no-git)   DO_GIT=0; shift ;;
        --force)    FORCE=1; shift ;;
        -*) echo "Unknown flag: $1" >&2; usage >&2; exit 1 ;;
        *)
            if [ -z "$TARGET" ]; then
                TARGET="$1"
            else
                echo "Error: unexpected extra argument: $1" >&2; usage >&2; exit 1
            fi
            shift ;;
    esac
done

case "$PROG_LANG" in
    go|sh) ;;
    *) echo "Unknown --lang: $PROG_LANG (go|sh)" >&2; exit 1 ;;
esac
case "$CI" in
    all)  CI="github,gitea,gitlab" ;;
    none) CI="" ;;
esac
CI_GITHUB=0
CI_GITEA=0
CI_GITLAB=0
for _ci in $(printf '%s' "$CI" | tr ',' ' '); do
    case "$_ci" in
        github) CI_GITHUB=1 ;;
        gitea)  CI_GITEA=1 ;;
        gitlab) CI_GITLAB=1 ;;
        *) echo "Unknown --ci: $_ci (github|gitea|gitlab|all|none)" >&2; exit 1 ;;
    esac
done

tpl_justfile_go() {
    cat <<'EOT'
bin := "__NAME__"
version_file := "versions.txt"
EOT
    tpl_vendor_env
    cat <<'EOT'

_default:
    @just --list

build:
    #!/usr/bin/env sh
    set -eu
    v=$(tr -d '[:space:]' < {{version_file}})
    u=$(git remote get-url origin 2>/dev/null || true)
    case "$u" in
        "")    o=local ;;
        *://*) h=${u#*://}; h=${h#*@}; o="https://${h%.git}" ;;
        *:*)   h=${u#*@};   o="https://$(printf '%s' "${h%.git}" | tr ':' '/')" ;;
        *)     o=local ;;
    esac
    if [ -f upstream.txt ]; then up=$(tr -d '[:space:]' < upstream.txt); else up="$o"; fi
    c=$(git rev-parse --short HEAD 2>/dev/null || true)
    CGO_ENABLED=0 go build -trimpath \
        -ldflags="-s -w -X main.version=$v -X main.origin=$o -X main.upstream=$up -X main.commit=$c -X main.channel=local" \
        -o {{bin}} __PKG__
    echo "Built: ./{{bin}} (v$v)"

test mask="":
    go test {{ if mask != "" { "-run " + mask } else { "" } }} ./...

vet:
    go vet ./...

fmt:
    go fmt ./...

check: vet test

check-conventions:
    check_install.sh --build .

clean:
    rm -f {{bin}}
    rm -rf dist

install: build
    install -d "$HOME/.local/bin"
    install -m 0755 {{bin}} "$HOME/.local/bin/{{bin}}"

uninstall:
    rm -f "$HOME/.local/bin/{{bin}}"

EOT
    tpl_vendor_recipes
    echo
    tpl_bump_recipes
    tpl_release_recipe
}

tpl_justfile_sh() {
    cat <<'EOT'
bin := "__NAME__"
src := "__SRC__"
version_file := "versions.txt"

_default:
    @just --list

build:
    #!/usr/bin/env sh
    set -eu
    v=$(tr -d '[:space:]' < {{version_file}})
    u=$(git remote get-url origin 2>/dev/null || true)
    case "$u" in
        "")    o=local ;;
        *://*) h=${u#*://}; h=${h#*@}; o="https://${h%.git}" ;;
        *:*)   h=${u#*@};   o="https://$(printf '%s' "${h%.git}" | tr ':' '/')" ;;
        *)     o=local ;;
    esac
    if [ -f upstream.txt ]; then up=$(tr -d '[:space:]' < upstream.txt); else up="$o"; fi
    c=$(git rev-parse --short HEAD 2>/dev/null || true)
    sed -e "s|^VERSION=\"dev\"$|VERSION=\"$v\"|" \
        -e "s|^ORIGIN=\"\"$|ORIGIN=\"$o\"|" \
        -e "s|^UPSTREAM=\"\"$|UPSTREAM=\"$up\"|" \
        -e "s|^COMMIT=\"\"$|COMMIT=\"$c\"|" \
        -e "s|^CHANNEL=\"\"$|CHANNEL=\"local\"|" \
        {{src}} > {{bin}}
    chmod 0755 {{bin}}
    echo "Built: ./{{bin}} (v$v)"

check:
    sh -n {{src}}

check-conventions:
    check_install.sh --build .

clean:
    rm -f {{bin}}
    rm -rf dist

install: build
    install -d "$HOME/.local/bin"
    install -m 0755 {{bin}} "$HOME/.local/bin/{{bin}}"

uninstall:
    rm -f "$HOME/.local/bin/{{bin}}"

EOT
    tpl_bump_recipes
    tpl_release_recipe
}

tpl_bump_recipes() {
    cat <<'EOT'
bump-patch: && (_bump-commit "patch")
    #!/usr/bin/env sh
    set -eu
    v=$(tr -d '[:space:]' < versions.txt)
    IFS=. read -r MAJ MIN PAT <<EOF
    $v
    EOF
    printf '%s.%s.%s\n' "$MAJ" "$MIN" "$((PAT + 1))" > versions.txt
    cat versions.txt

bump-minor: && (_bump-commit "minor")
    #!/usr/bin/env sh
    set -eu
    v=$(tr -d '[:space:]' < versions.txt)
    IFS=. read -r MAJ MIN PAT <<EOF
    $v
    EOF
    printf '%s.%s.0\n' "$MAJ" "$((MIN + 1))" > versions.txt
    cat versions.txt

bump-major: && (_bump-commit "major")
    #!/usr/bin/env sh
    set -eu
    v=$(tr -d '[:space:]' < versions.txt)
    IFS=. read -r MAJ MIN PAT <<EOF
    $v
    EOF
    printf '%s.0.0\n' "$((MAJ + 1))" > versions.txt
    cat versions.txt

_bump-commit level:
    #!/usr/bin/env sh
    set -eu
    v=$(tr -d '[:space:]' < versions.txt)
    if git rev-parse -q --verify "refs/tags/v$v" >/dev/null; then
        git checkout -- versions.txt
        echo "tag v$v already exists" >&2
        exit 1
    fi
    git commit -q -m "bump {{level}}" -- versions.txt
    git tag "v$v"
    rc=0
    for r in $(git remote); do
        git push -q "$r" HEAD --tags || { echo "push to $r failed" >&2; rc=1; }
    done
    echo "Tagged v$v"
    exit "$rc"

EOT
}

tpl_release_recipe() {
    cat <<'EOT'
release level="patch":
    #!/usr/bin/env sh
    set -eu
    case "{{level}}" in
        patch|minor|major) ;;
        *) echo "level must be patch, minor or major" >&2; exit 1 ;;
    esac
    git diff --quiet && git diff --cached --quiet || { echo "working tree is dirty" >&2; exit 1; }
    just bump-{{level}}
EOT
}

tpl_gitignore_go() {
    cat <<'EOT'
/__NAME__
/bin/
/dist/
/go.work
/go.work.sum
coverage.out
EOT
}

tpl_gitignore_sh() {
    cat <<'EOT'
/__NAME__
/dist/
EOT
}

tpl_main_go() {
    cat <<'EOT'
package main

import (
	"fmt"
	"os"

	"github.com/dimkarp93/install-libs/buildinfo"
)

var (
	version  string
	origin   string
	upstream string
	commit   string
	channel  string
)

func build() buildinfo.Info {
	return buildinfo.Info{
		Version:  version,
		Origin:   origin,
		Upstream: upstream,
		Commit:   commit,
		Channel:  channel,
	}
}

func usage(w *os.File) {
	fmt.Fprint(w, `Usage: __NAME__ [FLAGS]

  --version, -v   print the version
  --origin        print the repository the binary was built from
  --buildinfo     print the full build info
  -h, --help      show this help
`)
}

func run() {
	for _, a := range os.Args[1:] {
		if a == "-h" || a == "--help" {
			usage(os.Stdout)
			return
		}
	}
	usage(os.Stderr)
	os.Exit(2)
}

func main() {
	if build().Handle(os.Args[1:]) {
		return
	}
	run()
}
EOT
}

tpl_source_sh() {
    cat <<'EOT'
#!/bin/sh
set -eu

PROG=$(basename "$0")

VERSION="dev"
ORIGIN=""
UPSTREAM=""
COMMIT=""
CHANNEL=""

print_origin() {
    if [ -n "$ORIGIN" ]; then
        printf '%s\n' "$ORIGIN"
    else
        printf 'local\n'
    fi
}

print_buildinfo() {
    printf 'origin=%s\n' "$(print_origin)"
    if [ -n "$UPSTREAM" ]; then
        printf 'upstream=%s\n' "$UPSTREAM"
    else
        printf 'upstream=%s\n' "$(print_origin)"
    fi
    printf 'version=%s\n' "$VERSION"
    [ -n "$COMMIT" ] && printf 'commit=%s\n' "$COMMIT"
    [ -n "$CHANNEL" ] && printf 'channel=%s\n' "$CHANNEL"
    return 0
}

usage() {
    cat <<USAGE
Usage: $PROG [FLAGS]
       $PROG (--version | -v | --origin | --buildinfo)

  -h, --help      show this help
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version|-v) printf '%s\n' "$VERSION"; exit 0 ;;
        --origin)     print_origin; exit 0 ;;
        --buildinfo)  print_buildinfo; exit 0 ;;
        -h|--help)    usage; exit 0 ;;
        *)            usage >&2; exit 2 ;;
    esac
done

usage >&2
exit 2
EOT
}

tpl_readme() {
    cat <<'EOT'
# __NAME__

## Installation

```sh
github_install.sh __NAME__
```

From a working copy:

```sh
local_install.sh __NAME__
```

## Build

```sh
just build
./__NAME__ --version
```

## Release

```sh
just release patch
```

`versions.txt` is bumped and committed, the tag `vX.Y.Z` is created and pushed
together with the branch to every remote; the tag push starts the release workflow.

## Build info

```sh
__NAME__ --version
__NAME__ --origin
__NAME__ --buildinfo
```

The program follows the conventions from
<https://github.com/dimkarp93/install/blob/master/CONVENTIONS.md>.
EOT
}

tpl_workflow_go_github() {
    cat <<'EOT'
name: Release

on:
  push:
    tags: ['v*']

permissions:
  contents: write

jobs:
  release:
    if: github.server_url == 'https://github.com'
    runs-on: ubuntu-latest
    env:
      GOWORK: "off"
      GOFLAGS: -mod=vendor
    steps:
      - uses: actions/checkout@v4

      - name: Read version
        id: ver
        run: |
          tag="${GITHUB_REF#refs/tags/}"
          v="${tag#v}"
          if ! echo "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo "the tag must be vX.Y.Z (got: '$tag')" >&2
            exit 1
          fi
          bin="${{ github.event.repository.name }}"
          origin="${GITHUB_SERVER_URL%/}/${GITHUB_REPOSITORY}"
          if [ -f upstream.txt ]; then
            upstream=$(tr -d '[:space:]' < upstream.txt)
          else
            upstream="$origin"
          fi
          echo "version=$v"          >> "$GITHUB_OUTPUT"
          echo "tag=v$v"             >> "$GITHUB_OUTPUT"
          echo "bin=$bin"            >> "$GITHUB_OUTPUT"
          echo "origin=$origin"      >> "$GITHUB_OUTPUT"
          echo "upstream=$upstream"  >> "$GITHUB_OUTPUT"
          echo "commit=$(printf '%s' "$GITHUB_SHA" | cut -c1-7)" >> "$GITHUB_OUTPUT"

      - name: Setup Go
        uses: actions/setup-go@v5
        with:
          go-version-file: go.mod

      - name: Check vendor
        run: |
          go mod vendor
          if [ -n "$(git status --porcelain -- go.mod go.sum vendor/ | tee /dev/stderr)" ]; then
            echo "vendor/ does not match go.mod - run: just vendor" >&2
            exit 1
          fi

      - name: Run tests
        run: go test ./...

      - name: Build archives
        env:
          BIN: ${{ steps.ver.outputs.bin }}
          VERSION: ${{ steps.ver.outputs.version }}
          ORIGIN: ${{ steps.ver.outputs.origin }}
          UPSTREAM: ${{ steps.ver.outputs.upstream }}
          COMMIT: ${{ steps.ver.outputs.commit }}
          CHANNEL: github-release
        run: |
          set -euo pipefail
          mkdir -p dist
          for target in linux/amd64 linux/arm64 darwin/amd64 darwin/arm64; do
            os=${target%/*}
            arch=${target#*/}
            name="${BIN}-${os}-${arch}"
            out="dist/${name}.tar.gz"
            tmp=$(mktemp -d)
            CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" \
              go build -trimpath \
                -ldflags="-s -w -X main.version=${VERSION} -X main.origin=${ORIGIN} -X main.upstream=${UPSTREAM} -X main.commit=${COMMIT} -X main.channel=${CHANNEL}" \
                -o "$tmp/${BIN}" "./cmd/${BIN}"
            chmod +x "$tmp/${BIN}"
            tar -C "$tmp" -czf "$out" "${BIN}"
            rm -rf "$tmp"
          done
          (cd dist && sha256sum *.tar.gz > SHA256SUMS)
          ls -la dist

      - name: Create release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "${{ steps.ver.outputs.tag }}" \
            --title "${{ steps.ver.outputs.tag }}" \
            --notes "Automated release ${{ steps.ver.outputs.tag }}" \
            dist/*
EOT
}

tpl_workflow_go_gitea() {
    cat <<'EOT'
name: Release

on:
  push:
    tags: ['v*']

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        env:
          TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -eu
          auth=$(printf '%s:' "$TOKEN" | base64 | tr -d '\n')
          git init -q .
          git remote add origin "${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}.git"
          git config --local "http.extraheader" "Authorization: Basic ${auth}"
          git fetch -q --no-tags --depth=1 origin "$GITHUB_SHA"
          git checkout -q FETCH_HEAD

      - name: Read version
        id: ver
        run: |
          set -eu
          tag="${GITHUB_REF#refs/tags/}"
          v="${tag#v}"
          if ! echo "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo "the tag must be vX.Y.Z (got: '$tag')" >&2
            exit 1
          fi
          bin="${GITHUB_REPOSITORY##*/}"
          origin="${GITHUB_SERVER_URL%/}/${GITHUB_REPOSITORY}"
          if [ -f upstream.txt ]; then
            upstream=$(tr -d '[:space:]' < upstream.txt)
          else
            upstream="$origin"
          fi
          echo "version=$v"          >> "$GITHUB_OUTPUT"
          echo "tag=v$v"             >> "$GITHUB_OUTPUT"
          echo "bin=$bin"            >> "$GITHUB_OUTPUT"
          echo "origin=$origin"      >> "$GITHUB_OUTPUT"
          echo "upstream=$upstream"  >> "$GITHUB_OUTPUT"
          echo "commit=$(printf '%s' "$GITHUB_SHA" | cut -c1-7)" >> "$GITHUB_OUTPUT"

      - name: Setup Go
        run: |
          set -eu
          if [ ! -f go.mod ]; then
            echo "go.mod not found" >&2
            exit 1
          fi
          gv=$(awk '/^toolchain /{print $2; exit}' go.mod | sed 's/^go//')
          if [ -z "$gv" ]; then
            gv=$(awk '/^go /{print $2; exit}' go.mod)
          fi
          if [ -z "$gv" ]; then
            echo "failed to determine the Go version from go.mod" >&2
            exit 1
          fi
          case "$gv" in
            *.*.*) ;;
            *)
              json=$(curl -fsSL "https://go.dev/dl/?mode=json&include=all")
              full=$(printf '%s\n' "$json" \
                | grep -o "go${gv}\.[0-9]*" \
                | sort -V | tail -n1 | sed 's/^go//')
              gv="${full:-${gv}.0}"
              ;;
          esac
          case "$(uname -m)" in
            x86_64|amd64)  arch=amd64 ;;
            aarch64|arm64) arch=arm64 ;;
            *) echo "unsupported runner architecture: $(uname -m)" >&2; exit 1 ;;
          esac
          root="$HOME/.local"
          mkdir -p "$root"
          rm -rf "$root/go"
          os=$(uname -s | tr '[:upper:]' '[:lower:]')
          curl -fsSL "https://go.dev/dl/go${gv}.${os}-${arch}.tar.gz" -o "$root/go.tar.gz"
          tar -C "$root" -xzf "$root/go.tar.gz"
          rm -f "$root/go.tar.gz"
          echo "$root/go/bin" >> "$GITHUB_PATH"
          "$root/go/bin/go" version

      - name: Run tests
        run: go test ./...

      - name: Build archives
        env:
          BIN: ${{ steps.ver.outputs.bin }}
          VERSION: ${{ steps.ver.outputs.version }}
          ORIGIN: ${{ steps.ver.outputs.origin }}
          UPSTREAM: ${{ steps.ver.outputs.upstream }}
          COMMIT: ${{ steps.ver.outputs.commit }}
          CHANNEL: gitea-release
        run: |
          set -eu
          mkdir -p dist
          for target in linux/amd64 linux/arm64 darwin/amd64 darwin/arm64; do
            os=${target%/*}
            arch=${target#*/}
            name="${BIN}-${os}-${arch}"
            out="dist/${name}.tar.gz"
            tmp=$(mktemp -d)
            CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" \
              go build -trimpath \
                -ldflags="-s -w -X main.version=${VERSION} -X main.origin=${ORIGIN} -X main.upstream=${UPSTREAM} -X main.commit=${COMMIT} -X main.channel=${CHANNEL}" \
                -o "$tmp/${BIN}" "./cmd/${BIN}"
            chmod +x "$tmp/${BIN}"
            tar -C "$tmp" -czf "$out" "${BIN}"
            rm -rf "$tmp"
          done
          (cd dist && sha256sum *.tar.gz > SHA256SUMS)
          ls -la dist

      - name: Create release
        env:
          TOKEN: ${{ secrets.GITHUB_TOKEN }}
          TAG: ${{ steps.ver.outputs.tag }}
        run: |
          set -eu
          api="${GITHUB_SERVER_URL}/api/v1/repos/${GITHUB_REPOSITORY}"
          body=$(printf '{"tag_name":"%s","name":"%s","body":"Automated release %s"}' \
            "$TAG" "$TAG" "$TAG")
          resp=$(curl -fsS -X POST "${api}/releases" \
            -H "Authorization: token ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$body")
          if command -v jq >/dev/null 2>&1; then
            id=$(printf '%s' "$resp" | jq -r '.id')
          else
            id=$(printf '%s' "$resp" | grep -o '"id":[[:space:]]*[0-9]*' | head -n1 | tr -dc '0-9')
          fi
          if [ -z "$id" ]; then
            echo "failed to get the release id from the Gitea response: $resp" >&2
            exit 1
          fi
          for f in dist/*; do
            echo "Uploading $(basename "$f")"
            curl -fsS -X POST "${api}/releases/${id}/assets?name=$(basename "$f")" \
              -H "Authorization: token ${TOKEN}" \
              -F "attachment=@${f}" >/dev/null
          done
          echo "Release ${TAG} created"
EOT
}

tpl_workflow_sh_github() {
    cat <<'EOT'
name: Release

on:
  push:
    tags: ['v*']

permissions:
  contents: write

jobs:
  release:
    if: github.server_url == 'https://github.com'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Read version
        id: ver
        run: |
          tag="${GITHUB_REF#refs/tags/}"
          v="${tag#v}"
          if ! echo "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo "the tag must be vX.Y.Z (got: '$tag')" >&2
            exit 1
          fi
          bin="${{ github.event.repository.name }}"
          if [ -f "${bin}.sh" ]; then
            src="${bin}.sh"
          elif [ -f "${bin}-init.sh" ]; then
            src="${bin}-init.sh"
          else
            echo "source script not found: ${bin}.sh or ${bin}-init.sh" >&2
            exit 1
          fi
          origin="${GITHUB_SERVER_URL%/}/${GITHUB_REPOSITORY}"
          if [ -f upstream.txt ]; then
            upstream=$(tr -d '[:space:]' < upstream.txt)
          else
            upstream="$origin"
          fi
          echo "version=$v"          >> "$GITHUB_OUTPUT"
          echo "tag=v$v"             >> "$GITHUB_OUTPUT"
          echo "bin=$bin"            >> "$GITHUB_OUTPUT"
          echo "src=$src"            >> "$GITHUB_OUTPUT"
          echo "origin=$origin"      >> "$GITHUB_OUTPUT"
          echo "upstream=$upstream"  >> "$GITHUB_OUTPUT"
          echo "commit=$(printf '%s' "$GITHUB_SHA" | cut -c1-7)" >> "$GITHUB_OUTPUT"

      - name: Check the script
        run: sh -n "${{ steps.ver.outputs.src }}"

      - name: Build archives
        env:
          BIN: ${{ steps.ver.outputs.bin }}
          SRC: ${{ steps.ver.outputs.src }}
          VERSION: ${{ steps.ver.outputs.version }}
          ORIGIN: ${{ steps.ver.outputs.origin }}
          UPSTREAM: ${{ steps.ver.outputs.upstream }}
          COMMIT: ${{ steps.ver.outputs.commit }}
          CHANNEL: github-release
        run: |
          set -euo pipefail
          mkdir -p dist
          build=$(mktemp -d)
          sed -e "s|^VERSION=\"dev\"$|VERSION=\"${VERSION}\"|" \
              -e "s|^ORIGIN=\"\"$|ORIGIN=\"${ORIGIN}\"|" \
              -e "s|^UPSTREAM=\"\"$|UPSTREAM=\"${UPSTREAM}\"|" \
              -e "s|^COMMIT=\"\"$|COMMIT=\"${COMMIT}\"|" \
              -e "s|^CHANNEL=\"\"$|CHANNEL=\"${CHANNEL}\"|" \
              "$SRC" > "$build/${BIN}"
          chmod +x "$build/${BIN}"
          for target in linux/amd64 linux/arm64 darwin/amd64 darwin/arm64; do
            os=${target%/*}
            arch=${target#*/}
            tar -C "$build" -czf "dist/${BIN}-${os}-${arch}.tar.gz" "${BIN}"
          done
          rm -rf "$build"
          (cd dist && sha256sum *.tar.gz > SHA256SUMS)
          ls -la dist

      - name: Create release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "${{ steps.ver.outputs.tag }}" \
            --title "${{ steps.ver.outputs.tag }}" \
            --notes "Automated release ${{ steps.ver.outputs.tag }}" \
            dist/*
EOT
}

tpl_workflow_sh_gitea() {
    cat <<'EOT'
name: Release

on:
  push:
    tags: ['v*']

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        env:
          TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -eu
          auth=$(printf '%s:' "$TOKEN" | base64 | tr -d '\n')
          git init -q .
          git remote add origin "${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}.git"
          git config --local "http.extraheader" "Authorization: Basic ${auth}"
          git fetch -q --no-tags --depth=1 origin "$GITHUB_SHA"
          git checkout -q FETCH_HEAD

      - name: Read version
        id: ver
        run: |
          set -eu
          tag="${GITHUB_REF#refs/tags/}"
          v="${tag#v}"
          if ! echo "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo "the tag must be vX.Y.Z (got: '$tag')" >&2
            exit 1
          fi
          bin="${GITHUB_REPOSITORY##*/}"
          if [ -f "${bin}.sh" ]; then
            src="${bin}.sh"
          elif [ -f "${bin}-init.sh" ]; then
            src="${bin}-init.sh"
          else
            echo "source script not found: ${bin}.sh or ${bin}-init.sh" >&2
            exit 1
          fi
          origin="${GITHUB_SERVER_URL%/}/${GITHUB_REPOSITORY}"
          if [ -f upstream.txt ]; then
            upstream=$(tr -d '[:space:]' < upstream.txt)
          else
            upstream="$origin"
          fi
          echo "version=$v"          >> "$GITHUB_OUTPUT"
          echo "tag=v$v"             >> "$GITHUB_OUTPUT"
          echo "bin=$bin"            >> "$GITHUB_OUTPUT"
          echo "src=$src"            >> "$GITHUB_OUTPUT"
          echo "origin=$origin"      >> "$GITHUB_OUTPUT"
          echo "upstream=$upstream"  >> "$GITHUB_OUTPUT"
          echo "commit=$(printf '%s' "$GITHUB_SHA" | cut -c1-7)" >> "$GITHUB_OUTPUT"

      - name: Check the script
        run: sh -n "${{ steps.ver.outputs.src }}"

      - name: Build archives
        env:
          BIN: ${{ steps.ver.outputs.bin }}
          SRC: ${{ steps.ver.outputs.src }}
          VERSION: ${{ steps.ver.outputs.version }}
          ORIGIN: ${{ steps.ver.outputs.origin }}
          UPSTREAM: ${{ steps.ver.outputs.upstream }}
          COMMIT: ${{ steps.ver.outputs.commit }}
          CHANNEL: gitea-release
        run: |
          set -eu
          mkdir -p dist
          build=$(mktemp -d)
          sed -e "s|^VERSION=\"dev\"$|VERSION=\"${VERSION}\"|" \
              -e "s|^ORIGIN=\"\"$|ORIGIN=\"${ORIGIN}\"|" \
              -e "s|^UPSTREAM=\"\"$|UPSTREAM=\"${UPSTREAM}\"|" \
              -e "s|^COMMIT=\"\"$|COMMIT=\"${COMMIT}\"|" \
              -e "s|^CHANNEL=\"\"$|CHANNEL=\"${CHANNEL}\"|" \
              "$SRC" > "$build/${BIN}"
          chmod +x "$build/${BIN}"
          for target in linux/amd64 linux/arm64 darwin/amd64 darwin/arm64; do
            os=${target%/*}
            arch=${target#*/}
            tar -C "$build" -czf "dist/${BIN}-${os}-${arch}.tar.gz" "${BIN}"
          done
          rm -rf "$build"
          (cd dist && sha256sum *.tar.gz > SHA256SUMS)
          ls -la dist

      - name: Create release
        env:
          TOKEN: ${{ secrets.GITHUB_TOKEN }}
          TAG: ${{ steps.ver.outputs.tag }}
        run: |
          set -eu
          api="${GITHUB_SERVER_URL}/api/v1/repos/${GITHUB_REPOSITORY}"
          body=$(printf '{"tag_name":"%s","name":"%s","body":"Automated release %s"}' \
            "$TAG" "$TAG" "$TAG")
          resp=$(curl -fsS -X POST "${api}/releases" \
            -H "Authorization: token ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$body")
          if command -v jq >/dev/null 2>&1; then
            id=$(printf '%s' "$resp" | jq -r '.id')
          else
            id=$(printf '%s' "$resp" | grep -o '"id":[[:space:]]*[0-9]*' | head -n1 | tr -dc '0-9')
          fi
          if [ -z "$id" ]; then
            echo "failed to get the release id from the Gitea response: $resp" >&2
            exit 1
          fi
          for f in dist/*; do
            echo "Uploading $(basename "$f")"
            curl -fsS -X POST "${api}/releases/${id}/assets?name=$(basename "$f")" \
              -H "Authorization: token ${TOKEN}" \
              -F "attachment=@${f}" >/dev/null
          done
          echo "Release ${TAG} created"
EOT
}

tpl_workflow_go_gitlab() {
    cat <<'EOT'
release:
  image: golang:1
  rules:
    - if: '$CI_SERVER_HOST == "gitlab.com" && $CI_COMMIT_TAG =~ /^v[0-9]+\.[0-9]+\.[0-9]+$/'
  variables:
    CGO_ENABLED: "0"
    GOWORK: "off"
    GOFLAGS: -mod=vendor
    GOTOOLCHAIN: auto
    CHANNEL: gitlab-release
  script:
    - |
      set -eu
      TAG="$CI_COMMIT_TAG"
      VERSION="${TAG#v}"
      BIN="$CI_PROJECT_NAME"
      ORIGIN="${CI_PROJECT_URL%/}"
      if [ -f upstream.txt ]; then
        UPSTREAM=$(tr -d '[:space:]' < upstream.txt)
      else
        UPSTREAM="$ORIGIN"
      fi
      COMMIT=$(printf '%s' "$CI_COMMIT_SHA" | cut -c1-7)
      API="$CI_API_V4_URL/projects/$CI_PROJECT_ID"

      go mod vendor
      if [ -n "$(git status --porcelain -- go.mod go.sum vendor/ | tee /dev/stderr)" ]; then
        echo "vendor/ does not match go.mod - run: just vendor" >&2
        exit 1
      fi

      go test ./...

      mkdir -p dist
      for target in linux/amd64 linux/arm64 darwin/amd64 darwin/arm64; do
        os=${target%/*}
        arch=${target#*/}
        name="${BIN}-${os}-${arch}"
        out="dist/${name}.tar.gz"
        tmp=$(mktemp -d)
        GOOS="$os" GOARCH="$arch" \
          go build -trimpath \
            -ldflags="-s -w -X main.version=${VERSION} -X main.origin=${ORIGIN} -X main.upstream=${UPSTREAM} -X main.commit=${COMMIT} -X main.channel=${CHANNEL}" \
            -o "$tmp/${BIN}" "./cmd/${BIN}"
        chmod +x "$tmp/${BIN}"
        tar -C "$tmp" -czf "$out" "${BIN}"
        rm -rf "$tmp"
      done
      (cd dist && sha256sum *.tar.gz > SHA256SUMS)
      ls -la dist

      pkg_url="$API/packages/generic/${BIN}/${VERSION}"
      links=""
      for f in dist/*; do
        file=$(basename "$f")
        echo "Uploading $file"
        curl -fsS -H "JOB-TOKEN: $CI_JOB_TOKEN" --upload-file "$f" "$pkg_url/$file" >/dev/null
        link=$(printf '{"name":"%s","url":"%s/%s","direct_asset_path":"/%s","link_type":"package"}' \
          "$file" "$pkg_url" "$file" "$file")
        links="${links:+$links,}$link"
      done
      body=$(printf '{"tag_name":"%s","name":"%s","description":"Automated release %s","assets":{"links":[%s]}}' \
        "$TAG" "$TAG" "$TAG" "$links")
      curl -fsS -X POST "$API/releases" \
        -H "JOB-TOKEN: $CI_JOB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$body" >/dev/null
      echo "Release $TAG created"
EOT
}

tpl_workflow_sh_gitlab() {
    cat <<'EOT'
release:
  image: alpine:3
  rules:
    - if: '$CI_SERVER_HOST == "gitlab.com" && $CI_COMMIT_TAG =~ /^v[0-9]+\.[0-9]+\.[0-9]+$/'
  variables:
    CHANNEL: gitlab-release
  script:
    - apk add --no-cache curl >/dev/null
    - |
      set -eu
      TAG="$CI_COMMIT_TAG"
      VERSION="${TAG#v}"
      BIN="$CI_PROJECT_NAME"
      if [ -f "${BIN}.sh" ]; then
        SRC="${BIN}.sh"
      elif [ -f "${BIN}-init.sh" ]; then
        SRC="${BIN}-init.sh"
      else
        echo "source script not found: ${BIN}.sh or ${BIN}-init.sh" >&2
        exit 1
      fi
      ORIGIN="${CI_PROJECT_URL%/}"
      if [ -f upstream.txt ]; then
        UPSTREAM=$(tr -d '[:space:]' < upstream.txt)
      else
        UPSTREAM="$ORIGIN"
      fi
      COMMIT=$(printf '%s' "$CI_COMMIT_SHA" | cut -c1-7)
      API="$CI_API_V4_URL/projects/$CI_PROJECT_ID"

      sh -n "$SRC"

      mkdir -p dist
      build=$(mktemp -d)
      sed -e "s|^VERSION=\"dev\"$|VERSION=\"${VERSION}\"|" \
          -e "s|^ORIGIN=\"\"$|ORIGIN=\"${ORIGIN}\"|" \
          -e "s|^UPSTREAM=\"\"$|UPSTREAM=\"${UPSTREAM}\"|" \
          -e "s|^COMMIT=\"\"$|COMMIT=\"${COMMIT}\"|" \
          -e "s|^CHANNEL=\"\"$|CHANNEL=\"${CHANNEL}\"|" \
          "$SRC" > "$build/${BIN}"
      chmod +x "$build/${BIN}"
      for target in linux/amd64 linux/arm64 darwin/amd64 darwin/arm64; do
        os=${target%/*}
        arch=${target#*/}
        tar -C "$build" -czf "dist/${BIN}-${os}-${arch}.tar.gz" "${BIN}"
      done
      rm -rf "$build"
      (cd dist && sha256sum *.tar.gz > SHA256SUMS)
      ls -la dist

      pkg_url="$API/packages/generic/${BIN}/${VERSION}"
      links=""
      for f in dist/*; do
        file=$(basename "$f")
        echo "Uploading $file"
        curl -fsS -H "JOB-TOKEN: $CI_JOB_TOKEN" --upload-file "$f" "$pkg_url/$file" >/dev/null
        link=$(printf '{"name":"%s","url":"%s/%s","direct_asset_path":"/%s","link_type":"package"}' \
          "$file" "$pkg_url" "$file" "$file")
        links="${links:+$links,}$link"
      done
      body=$(printf '{"tag_name":"%s","name":"%s","description":"Automated release %s","assets":{"links":[%s]}}' \
        "$TAG" "$TAG" "$TAG" "$links")
      curl -fsS -X POST "$API/releases" \
        -H "JOB-TOKEN: $CI_JOB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$body" >/dev/null
      echo "Release $TAG created"
EOT
}

tpl_vendor_env() {
    cat <<'EOT'
export GOWORK := "off"
export GOFLAGS := "-mod=vendor"
EOT
}

tpl_vendor_recipes() {
    cat <<'EOT'
vendor:
    GOWORK=off go mod tidy
    GOWORK=off go mod vendor

vendor-check:
    GOWORK=off go mod vendor
    test -z "$(git status --porcelain -- go.mod go.sum vendor/ | tee /dev/stderr)"
EOT
}

tpl_gitattributes_vendor() {
    cat <<'EOT'
vendor/** linguist-generated=true -diff
EOT
}

emit() {
    _fn="tpl_$(printf '%s' "$1" | tr '-' '_')"
    case "$_fn" in
        tpl_justfile_go|tpl_justfile_sh|tpl_main_go|tpl_source_sh|tpl_gitignore_go|\
tpl_gitignore_sh|tpl_readme|tpl_bump_recipes|tpl_release_recipe|\
tpl_workflow_go_github|tpl_workflow_go_gitea|tpl_workflow_sh_github|tpl_workflow_sh_gitea|\
tpl_workflow_go_gitlab|tpl_workflow_sh_gitlab|tpl_vendor_env|tpl_vendor_recipes|tpl_gitattributes_vendor) ;;
        *) echo "Unknown template: $1" >&2; usage >&2; exit 1 ;;
    esac
    "$_fn"
}

if [ -n "$EMIT" ]; then
    emit "$EMIT"
    exit 0
fi

if [ -z "$TARGET" ]; then
    echo "Error: repository name or path is required" >&2; usage >&2; exit 1
fi

expand_tilde() {
    case "$1" in
        "~/"*) printf '%s' "$HOME/${1#~/}" ;;
        "~")   printf '%s' "$HOME" ;;
        *)     printf '%s' "$1" ;;
    esac
}

TARGET=$(expand_tilde "$TARGET")

case "$TARGET" in
    /*) DIR="$TARGET" ;;
    *)  DIR="$PWD/$TARGET" ;;
esac

NAME=$(basename "$DIR")
case "$NAME" in
    ""|.|..) echo "Error: cannot derive the program name from '$TARGET'" >&2; exit 1 ;;
esac

if [ -d "$DIR" ] && [ "$FORCE" = "0" ]; then
    if [ -n "$(ls -A "$DIR" 2>/dev/null)" ]; then
        echo "Error: directory is not empty: $DIR (use --force to fill it)" >&2; exit 1
    fi
fi

SRC="${NAME}.sh"
PKG="./cmd/${NAME}"

MODULE=""
if [ "$PROG_LANG" = "go" ]; then
    if [ -z "$OWNER" ]; then
        echo "Error: --owner is required for --lang go" >&2; exit 1
    fi
    MODULE="${HOST}/${OWNER}/${NAME}"
fi

render() {
    emit "$1" | sed \
        -e "s|__NAME__|${NAME}|g" \
        -e "s|__MODULE__|${MODULE}|g" \
        -e "s|__PKG__|${PKG}|g" \
        -e "s|__SRC__|${SRC}|g"
}

write_file() {
    _p="$DIR/$1"
    if [ -e "$_p" ]; then
        printf '  [skip] %s (exists)\n' "$1"
        return 0
    fi
    mkdir -p "$(dirname "$_p")"
    render "$2" > "$_p"
    printf '  [new]  %s\n' "$1"
}

write_text() {
    _p="$DIR/$1"
    if [ -e "$_p" ]; then
        printf '  [skip] %s (exists)\n' "$1"
        return 0
    fi
    mkdir -p "$(dirname "$_p")"
    printf '%s\n' "$2" > "$_p"
    printf '  [new]  %s\n' "$1"
}

go_directive() {
    _gv=""
    if command -v go >/dev/null 2>&1; then
        _gv=$(go env GOVERSION 2>/dev/null | sed -e 's/^go//' -e 's/^\([0-9][0-9]*\.[0-9][0-9]*\).*$/\1/')
    fi
    case "$_gv" in
        [0-9]*.[0-9]*) printf '%s' "$_gv" ;;
        *) printf '1.24' ;;
    esac
}

mkdir -p "$DIR"
DIR=$(cd "$DIR" && pwd)

echo "Creating: $DIR (lang=$PROG_LANG, name=$NAME)"
echo

write_text versions.txt "0.1.0"
if [ -n "$UPSTREAM_URL" ]; then
    write_text upstream.txt "$UPSTREAM_URL"
fi
write_file README.md readme

if [ "$PROG_LANG" = "go" ]; then
    write_file .gitignore gitignore-go
    write_file justfile justfile-go
    write_file "cmd/${NAME}/main.go" main-go
    write_text go.mod "module ${MODULE}

go $(go_directive)"
else
    write_file .gitignore gitignore-sh
    write_file justfile justfile-sh
    write_file "$SRC" source-sh
    chmod 0755 "$DIR/$SRC"
fi

if [ "$CI_GITHUB" = "1" ]; then
    write_file .github/workflows/release.yml "workflow-${PROG_LANG}-github"
fi
if [ "$CI_GITEA" = "1" ]; then
    write_file .gitea/workflows/release.yml "workflow-${PROG_LANG}-gitea"
fi
if [ "$CI_GITLAB" = "1" ]; then
    write_file .gitlab-ci.yml "workflow-${PROG_LANG}-gitlab"
fi

if [ "$PROG_LANG" = "go" ]; then
    write_file .gitattributes gitattributes-vendor
fi

if [ "$PROG_LANG" = "go" ] && command -v go >/dev/null 2>&1; then
    echo
    echo "Resolving dependencies:"
    if (cd "$DIR" && go get github.com/dimkarp93/install-libs/buildinfo >/dev/null 2>&1 \
        && go mod tidy >/dev/null 2>&1); then
        echo "  [OK]   github.com/dimkarp93/install-libs/buildinfo"
    else
        echo "  [WARN] failed to fetch install-libs - run 'go get github.com/dimkarp93/install-libs/buildinfo && go mod tidy' when the network is available"
    fi
    if (cd "$DIR" && GOWORK=off go mod vendor >/dev/null 2>&1); then
        echo "  [OK]   vendor/"
    else
        echo "  [WARN] go mod vendor failed - run 'just vendor' when the network is available"
    fi
fi

if [ "$DO_GIT" = "1" ] && command -v git >/dev/null 2>&1; then
    echo
    echo "git:"
    if [ -d "$DIR/.git" ]; then
        echo "  [skip] .git already exists"
    else
        (cd "$DIR" && git init -q)
        echo "  [new]  .git"
    fi
    if [ -n "$REMOTE_URL" ]; then
        if (cd "$DIR" && git remote get-url origin >/dev/null 2>&1); then
            echo "  [skip] remote origin already set"
        else
            (cd "$DIR" && git remote add origin "$REMOTE_URL")
            echo "  [new]  remote origin = $REMOTE_URL"
        fi
    fi
    if [ -z "$(cd "$DIR" && git log -1 --oneline 2>/dev/null || true)" ]; then
        if (cd "$DIR" && git add -A && git commit -q -m "initial commit" 2>/dev/null); then
            echo "  [new]  initial commit"
        else
            echo "  [WARN] failed to create the first commit (is git user.name/user.email set?)"
        fi
    else
        echo "  [skip] the repository already has commits"
    fi
fi

CHECKER=""
_self_dir=$(cd "$(dirname "$0")" && pwd)
if [ -x "$_self_dir/check_install.sh" ]; then
    CHECKER="$_self_dir/check_install.sh"
elif command -v check_install.sh >/dev/null 2>&1; then
    CHECKER="check_install.sh"
fi

echo
if [ -n "$CHECKER" ]; then
    "$CHECKER" "$DIR" || true
else
    echo "check_install.sh not found - skipping the conventions check"
fi

echo
echo "Done. Next steps:"
echo "  cd $DIR"
echo "  just build && ./$NAME --buildinfo"
