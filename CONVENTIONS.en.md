# Requirements for installable programs

*Languages: **English** · [Русский](CONVENTIONS.ru.md)*

To make a program installable and updatable with the installers from this repository — both from
GitHub / GitLab / Gitea Releases (`github_install.sh`, `gitlab_install.sh`, `gitea_install.sh`) and
locally from a working copy (`local_install.sh`) — it must satisfy the requirements described below.

The program may be written in any language: the installers only care about a ready-made executable
and about following the conventions for names, archives and versions.

## General requirements

### 1. Executable name

The executable name matches the repository directory name (which is also the repository name on
GitHub, the last segment of `owner/NAME`). The installers and the release workflow derive the
executable name from the directory (repository) name: directory `<name>` → executable `<name>`.

If the program must be named differently (for example, a git remote helper has to be called
`git-remote-<transport>` so that git finds it in `PATH`), the repository should be given the same
name as the executable.

### 2. File names in a release

Archives for every supported platform are attached to the release:

```
<name>-linux-amd64.tar.gz
<name>-linux-arm64.tar.gz
<name>-darwin-amd64.tar.gz
<name>-darwin-arm64.tar.gz
```

Here `<name>` is the executable name (see item 1).

### 3. The SHA256SUMS file

The same release also carries a `SHA256SUMS` file — the output of `sha256sum *.tar.gz`.
The installer verifies the archive integrity against this file before extracting it.

### 4. Archive layout

The executable `<name>` resides in one of two places inside the archive:

- in the root: `<name>`
- in a directory named after the platform: `<name>-<os>-<arch>/<name>`

There are no other mandatory files in the archive.

### 5. Local build (for `local_install.sh`)

The repository provides a `just build` target (in a `Justfile`) **or** `make build` (in a
`Makefile`) that puts the executable `<name>` (see item 1) into the **repository root**. A Go
program is built from `vendor/` only (see [vendoring](#go-programs-vendoring-required)).
`local_install.sh` uses this target to install the program locally, before a GitHub Release is
published.

```
<repository-root>/<name>   <- the executable must end up here after just/make build
```

## Go programs: layout (required)

`package main` of a Go program lives in `cmd/<name>/`, where `<name>` is the executable name (item 1
of the general requirements); the module root holds no `package main`:

```
<root>/go.mod             module github.com/owner/<name>
<root>/cmd/<name>/main.go package main
```

The build recipes and the release workflows build exactly this package (`./cmd/<name>`). Files the
program embeds with `//go:embed` live next to it, inside `cmd/<name>/`. The rest of the code lives in
`internal/` or in other packages of the module.

`go install` derives the executable name from the last segment of the **package** path, so
`go install github.com/owner/<name>/cmd/<name>@vX.Y.Z` produces a binary with the correct name.

## Go programs: requirements for `go install` (optional)

This section applies **only if** the program is meant to be installed with `go_install.sh` (that
is, with the standard `go install`). It is not needed for installation via `github_install.sh`,
`gitlab_install.sh`, `gitea_install.sh` and `local_install.sh`: the general requirements above are enough there, and the
language of the program does not matter.

### 1. Module path — a network address

In `go.mod` the module path must point at the real repository address:

```
module github.com/<owner>/<name>
module <gitea-host>/<owner>/<name>
```

A bare name (`module secrets`) makes `go install` impossible: `go` does not know where to fetch the
module from. The last segment of the module path matches the repository name and the executable
name (item 1 of the general requirements).

### 2. Dependencies must be published

`go install <package>@<version>` builds the module in isolation from the working copy:

- `go.work` is **ignored** — the local `replace` directives from it are not applied;
- `replace` in `go.mod` itself is not supported and causes an error.

Therefore every internal dependency must be published as a separate module with a semver tag and be
present in `go.sum`. There are no local `replace` directives either: to use a change of a
dependency, publish it and re-vendor (see [vendoring](#go-programs-vendoring-required)).

### 3. Major versions

Starting from `v2.0.0` the module path must carry a major-version suffix:

```
module github.com/owner/<name>/v2
```

Otherwise `go install <module>@v2.0.0` fails. `go_install.sh` takes the suffix into account when
computing the binary name.

### 4. The version under `go install`

`versions.txt` remains the source of truth for the release workflows and for `local_install.sh`.
But under `go install` the build runs without the `-ldflags` that the workflow sets, so
`-X main.version` has no effect and `--version` prints an empty string.

To make the `--version` flag work in both cases, take the version from the module metadata when
`main.version` is not set:

```go
var version string

func Version() string {
    if version != "" {
        return version
    }
    if info, ok := debug.ReadBuildInfo(); ok {
        if v := info.Main.Version; v != "" && v != "(devel)" {
            return strings.TrimPrefix(v, "v")
        }
    }
    return "dev"
}
```

This is a recommendation, not a requirement: when installing from release archives the version is
set by the workflow as before.

## Versions

### Semantic release tag

Releases are published through GitHub Releases, GitLab Releases or Gitea Releases. The tag of every release is
strictly `vMAJOR.MINOR.PATCH` (for example, `v1.2.3`).

### The version lives in `versions.txt`

The repository root holds a `versions.txt` file with the version in semver format without the `v`
prefix (for example, `0.4.0`). The version is embedded into the executable at build time (for
example, through `ldflags`).

### The `--version` flag

When started with the `--version` flag (or `-v`), the executable prints to standard output a line
with the version in semver format:

```
0.4.0
```

Without the `v` prefix and without any extra text — just the version number on its own line.

### Version bump recipes

For bumping the version the repository provides `bump-patch`, `bump-minor`, `bump-major` targets in
its `Justfile` (or `Makefile`). Each of them increments the corresponding version component in
`versions.txt` (zeroing the lower components):

- `bump-patch`: `1.2.3` → `1.2.4`
- `bump-minor`: `1.2.3` → `1.3.0`
- `bump-major`: `1.2.3` → `2.0.0`

and then publishes it:

1. commits `versions.txt` alone with the message `bump <patch|minor|major>`;
2. creates the tag `vX.Y.Z` (refusing and restoring `versions.txt` if the tag already exists);
3. runs `git push <remote> HEAD --tags` for every remote from `git remote`.

An example of the targets for a `Justfile`:

```just
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
```

For a `Makefile` the same steps live in a helper target that every `bump-*` target calls:

```make
bump-patch:
	@v=$$(tr -d '[:space:]' < versions.txt); \
	MAJ=$${v%%.*}; rest=$${v#*.}; MIN=$${rest%%.*}; PAT=$${rest##*.}; \
	printf '%s.%s.%s\n' "$$MAJ" "$$MIN" "$$((PAT + 1))" > versions.txt; \
	cat versions.txt
	@$(MAKE) --no-print-directory _bump-commit LEVEL=patch

_bump-commit:
	@v=$$(tr -d '[:space:]' < versions.txt); \
	if git rev-parse -q --verify "refs/tags/v$$v" >/dev/null; then \
		git checkout -- versions.txt; echo "tag v$$v already exists" >&2; exit 1; \
	fi; \
	git commit -q -m "bump $(LEVEL)" -- versions.txt && git tag "v$$v" || exit 1; \
	rc=0; for r in $$(git remote); do \
		git push -q "$$r" HEAD --tags || { echo "push to $$r failed" >&2; rc=1; }; \
	done; \
	echo "Tagged v$$v"; exit $$rc
```

Cutting a new version is a single command: `just bump-patch` / `make bump-patch` (or `bump-minor` /
`bump-major`) on `main` / `master`. The pushed tag starts the release workflow.

## Origin

A program can live in several repositories at once — an upstream on GitHub and one or more mirrors
(for example, a self-hosted Gitea). By the installed executable alone it is then impossible to tell
where it came from. To make that visible, the source repository is embedded into the executable at
build time, next to the version.

Two values are embedded:

- `origin` — the repository the executable was actually built from (the mirror);
- `upstream` — the canonical repository of the project (where issues go).

For a program with no mirrors both values coincide.

### 1. The `--origin` flag

When started with the `--origin` flag, the executable prints to standard output a single line with
the URL of the repository it was built from:

```
https://gitea.example.org/dima/mytool
```

Without any extra text — just the URL on its own line, in the canonical form (see item 3). If the
executable was built from a working copy without a remote, the line is the literal `local`.

### 2. The `--buildinfo` flag

Everything else about the build is reported by a separate `--buildinfo` flag, as `key=value` lines
in a fixed order:

```
origin=https://gitea.example.org/dima/mytool
upstream=https://github.com/dimkarp93/mytool
version=0.4.0
commit=431b60b
channel=gitea-release
```

The `origin`, `upstream` and `version` keys are always printed; `commit` and `channel` are omitted
when unknown. `channel` describes how the executable was produced: `github-release`,
`gitlab-release`, `gitea-release`, `local` or `go-install`.

One flag holds the whole set, so new build attributes do not require a new flag every time — only a
new line in the output.

### 3. Canonical URL form

The embedded URL must be canonical: scheme `https`, no user info, no `.git` suffix, no trailing
slash.

```
https://<host>/<owner>/<name>
```

This is a **requirement**, not a formatting preference. `git remote get-url origin` may return
`https://user:token@host/owner/repo.git` or `git@host:owner/repo.git`; embedding such a string
verbatim leaks a token or an internal host name into an executable that later ends up in a public
release. The URL is therefore normalised before it is embedded: the user info is dropped and the ssh
form is converted to https.

A snippet for a `Justfile` / `Makefile` build target:

```sh
u=$(git remote get-url origin 2>/dev/null || true)
case "$u" in
    "")    o=local ;;
    *://*) h=${u#*://}; h=${h#*@}; o="https://${h%.git}" ;;
    *:*)   h=${u#*@};   o="https://$(printf '%s' "${h%.git}" | tr ':' '/')" ;;
    *)     o=local ;;
esac
```

The snippet keeps the port, so an ssh remote on a non-standard port (`ssh://git@host:2222/o/r`)
yields `https://host:2222/o/r` — an ssh port is not an https port. For such a repository the origin
is set explicitly in the build target instead of being derived from the remote.

In CI no normalisation is needed: `${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}` (GitHub, Gitea) and
`$CI_PROJECT_URL` (GitLab) are already canonical. The release workflows from this repository build
the value that way.

### 4. The `upstream.txt` file

The canonical repository is declared by an optional `upstream.txt` file in the repository root — a
single line with the URL in the canonical form:

```
https://github.com/dimkarp93/mytool
```

If the file is absent, `upstream` equals `origin`. Adding the file makes sense in mirrors: there
`origin` points at the mirror while `upstream` keeps pointing at the source of truth.

### 5. Origin under `go install`

As with the version (see the `go install` section above), a build made by `go install` carries no
`-ldflags`, so `main.origin` stays empty. The module path is exactly the repository the module was
fetched from, so it serves as the fallback:

```go
var (
    version  string
    origin   string
    upstream string
    commit   string
    channel  string
)

func Origin() string {
    if origin != "" {
        return origin
    }
    if info, ok := debug.ReadBuildInfo(); ok && info.Main.Path != "" {
        p := info.Main.Path
        if i := strings.LastIndex(p, "/v"); i > 0 {
            if _, err := strconv.Atoi(p[i+2:]); err == nil {
                p = p[:i]
            }
        }
        return "https://" + p
    }
    return "unknown"
}
```

The major-version suffix (`/v2`, `/v3`) is stripped so that the URL points at the repository rather
than at a module path.

## Go programs: vendoring (required)

A Go program keeps its dependencies in `vendor/` and is built **only** from it — both in the release
workflow and locally (`just build`, `make build`, `local_install.sh`). The build does not depend on a
module proxy, on the module cache or on sibling working copies wired in through `go.work`, so it can
be repeated in an isolated network.

- If `go.mod` has `require` directives, `vendor/` with `vendor/modules.txt` is committed and matches
  the result of `GOWORK=off go mod vendor`. A module without dependencies needs no `vendor/`.
- `vendor/` is not listed in `.gitignore`; `.gitattributes` holds
  `vendor/** linguist-generated=true -diff`.
- The build file exports `GOWORK=off` and `GOFLAGS=-mod=vendor`, so that every recipe (`build`,
  `test`, `vet`, `install`, ...) uses `vendor/` only:

  ```just
  export GOWORK := "off"
  export GOFLAGS := "-mod=vendor"
  ```

  ```make
  export GOWORK := off
  export GOFLAGS := -mod=vendor
  ```

  `go.work` is not used: the repository does not keep one, and `GOWORK=off` also shields the build
  from a `go.work` in a parent directory (Go looks for it up the tree). To use a change of a
  dependency, publish it and run `just vendor`.
- Formatting must not touch `vendor/`: use `go fmt ./...` rather than `gofmt -w .`.
- The build file provides the `vendor` and `vendor-check` recipes. `vendor-check` looks at
  `git status`, not only at `git diff`, so that files missing from the committed `vendor/` are caught
  too:

```just
vendor:
    GOWORK=off go mod tidy
    GOWORK=off go mod vendor

vendor-check:
    GOWORK=off go mod vendor
    test -z "$(git status --porcelain -- go.mod go.sum vendor/ | tee /dev/stderr)"
```

After `go get` run `just vendor`: otherwise the build fails with "inconsistent vendoring". The
release workflows run the same check before building (`GOWORK=off`, `GOFLAGS=-mod=vendor`), and
`check_install.sh` fails a repository that does not follow this section.

Vendoring does not lift the requirements of the `go install` section: `go install` ignores
`vendor/`, so dependencies are still published as modules with semver tags. The code in `vendor/` is
redistributed together with the repository — the licenses of the dependencies must allow that.

## Recommendations

### Static build

Build without depending on system libraries (for Go — `CGO_ENABLED=0` and `-trimpath` plus the
`-ldflags` carrying the version and the origin). This guarantees that the executable runs on any
Linux / macOS without external dependencies.

```
-ldflags="-s -w -X main.version=${VERSION} -X main.origin=${ORIGIN} -X main.upstream=${UPSTREAM} -X main.commit=${COMMIT} -X main.channel=${CHANNEL}"
```

### Origin is not a trust anchor

The origin is self-declared: a rebuild can claim any URL, and nothing in the executable proves the
claim. The value is meant for diagnostics — "which mirror does this binary come from" — and must not
be used to make trust decisions.

In particular, an updater must never fetch code or releases from a URL taken out of an executable
without checking it against a host allowlist configured by the user.

### Embedding the origin breaks bit-for-bit reproducibility

Two builds of the same commit made in different mirrors produce different executables, because the
embedded `origin` differs. The `SHA256SUMS` files of releases published by different mirrors
therefore cannot be compared with each other. Each mirror is a release channel of its own; compare
checksums only within one channel.

### The release is triggered by the tag

The release workflow runs on a push of a `v*` tag (GitHub / Gitea: `on.push.tags`, GitLab:
`$CI_COMMIT_TAG`), not on a push to the branch. The version is taken from the tag name, so the
workflow neither reads `versions.txt` nor creates tags: the tag is made and pushed by the `bump-*`
recipes. A plain push to `master` does not start a release at all.

### The release workflow runs only on its own public domain

The GitHub template runs only on `github.com`, the GitLab template only on `gitlab.com`:

```yaml
# .github/workflows/release.yml
jobs:
  release:
    if: github.server_url == 'https://github.com'

# .gitlab-ci.yml
release:
  rules:
    - if: '$CI_SERVER_HOST == "gitlab.com" && $CI_COMMIT_TAG =~ /^v[0-9]+\.[0-9]+\.[0-9]+$/'
```

In mirrors on other instances (a private GitHub Enterprise, an internal GitLab, a Gitea reading
`.github/workflows`) the job is skipped. Such mirrors build releases with their own means; these
conventions do not regulate that. `check_install.sh` fails a GitHub / GitLab release workflow
without the guard.

### Reusable workflow

Use the template from this repository — it already implements all the conventions: computing the
executable name (from the repository name), building for four platforms, generating `SHA256SUMS`,
starting on a `vX.Y.Z` tag.

- GitHub Actions: `workflows/release.yml` → `.github/workflows/release.yml`
- GitLab CI: `workflows/release-gitlab.yml` → `.gitlab-ci.yml`
- Gitea Actions: `workflows/release-gitea.yml` → `.gitea/workflows/release.yml`

For shell programs: `release-sh.yml`, `release-sh-gitlab.yml`, `release-sh-gitea.yml`.

The templates are interchangeable: the archive names, `SHA256SUMS` and the `vX.Y.Z` tag format are
identical, so the installers of all platforms work the same way. The GitLab template uploads the
archives into the project's generic package registry and attaches them to the release as release
links (not as attachments). The
Gitea template uses no external actions (checkout, installing Go and publishing the release are
shell `run:` steps, the release is created through the Gitea API), so it also works where the
runner cannot download actions from github.com.

### Installer sources

- `github_install.sh` takes the instance from `-s` / `GITHUB_URL` (default `https://github.com`), the
  API from `GITHUB_API_URL` (default `https://api.github.com`, for other instances
  `<GITHUB_URL>/api/v3`), the token from `GITHUB_TOKEN`;
- `gitlab_install.sh` takes the instance from `-s` / `GITLAB_URL` (default `https://gitlab.com`), the
  token from `GITLAB_TOKEN` (scope `read_api`);
- `gitea_install.sh` takes the instance from `-s` / `GITEA_URL`, the token from `GITEA_TOKEN`;
- `go_install.sh` always installs from public `github.com` through the standard Go module mechanism
  and ignores `GITHUB_URL` / `GITLAB_URL`: `go install` finds a module by its path, not by a URL, so
  installing from a mirror would require redirecting git and resolving the checksum database. Use the
  release installers for mirrors.

### Scaffolding and checking

A repository that satisfies everything described above is created by `init_install.sh` from this
repository:

```sh
init_install.sh --lang go --owner <owner> <name>
init_install.sh --lang sh <name>
```

It writes `versions.txt`, the `justfile` with the `build` / `bump-*` / `release` recipes,
`.gitignore`, the release workflows (`--ci github,gitlab,gitea`, `all`, `none`) and a skeleton with
`--version` / `--origin` / `--buildinfo` (for Go — through `install-libs/buildinfo`). For Go it
also fills `vendor/`, `.gitattributes`, the `GOWORK` / `GOFLAGS` exports and the `vendor` /
`vendor-check` recipes.

An existing repository is checked by `check_install.sh` (with `--build` it also builds the binary,
inspects the output of the flags and checks that `vendor/` is consistent), and
`check_install.sh --fix` adds the missing pieces: `versions.txt`, `.gitignore`, the `bump-*` recipes,
the release workflow and, for Go, `vendor/`, `.gitattributes`, the `GOWORK` / `GOFLAGS` exports and
the `vendor-*` recipes (a `Makefile` gets a hint instead).
