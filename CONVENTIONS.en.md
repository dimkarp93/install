# Requirements for installable programs

*Languages: **English** · [Русский](CONVENTIONS.ru.md)*

To make a program installable and updatable with the installers from this repository — both from
GitHub Releases (`github_install.sh`) and locally from a working copy (`local_install.sh`) — it
must satisfy the requirements described below.

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
`Makefile`) that puts the executable `<name>` (see item 1) into the **repository root**.
`local_install.sh` uses this target to install the program locally, before a GitHub Release is
published.

```
<repository-root>/<name>   <- the executable must end up here after just/make build
```

## Go programs: requirements for `go install` (optional)

This section applies **only if** the program is meant to be installed with `go_install.sh` (that
is, with the standard `go install`). It is not needed for installation via `github_install.sh`,
`gitea_install.sh` and `local_install.sh`: the general requirements above are enough there, and the
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

### 2. Location of `package main` — `cmd/<name>/`

`go install` derives the executable name from the last segment of the **package** path, not of the
module. Hence the recommended layout:

```
<root>/go.mod            module github.com/owner/<name>
<root>/cmd/<name>/main.go package main
```

Then `go install github.com/owner/<name>/cmd/<name>@vX.Y.Z` produces a binary with the correct
name. `go_install.sh` tries this path first.

Keeping `package main` in the module root also works (`go_install.sh` uses it as a fallback), but
library code in such a module cannot be imported separately from `main` — if the module is also
meant to be a library, use `cmd/<name>/`.

### 3. Dependencies must be published

`go install <package>@<version>` builds the module in isolation from the working copy:

- `go.work` is **ignored** — the local `replace` directives from it are not applied;
- `replace` in `go.mod` itself is not supported and causes an error.

Therefore every internal dependency must be published as a separate module with a semver tag and be
present in `go.sum`. Keep local `replace` directives for development in `go.work` only (which does
not interfere with `go install`).

### 4. Major versions

Starting from `v2.0.0` the module path must carry a major-version suffix:

```
module github.com/owner/<name>/v2
```

Otherwise `go install <module>@v2.0.0` fails. `go_install.sh` takes the suffix into account when
computing the binary name.

### 5. The version under `go install`

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

Releases are published through GitHub Releases or Gitea Releases. The tag of every release is
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
`versions.txt` (zeroing the lower components) — following the release tooling style (see the
`Justfile` style of the `jira` tool):

- `bump-patch`: `1.2.3` → `1.2.4`
- `bump-minor`: `1.2.3` → `1.3.0`
- `bump-major`: `1.2.3` → `2.0.0`

An example of the targets for a `Justfile`:

```just
bump-patch:
    #!/usr/bin/env sh
    set -eu
    v=$(tr -d '[:space:]' < versions.txt)
    IFS=. read -r MAJ MIN PAT <<EOF
    $v
    EOF
    printf '%s.%s.%s\n' "$MAJ" "$MIN" "$((PAT + 1))" > versions.txt
    cat versions.txt

bump-minor:
    #!/usr/bin/env sh
    set -eu
    v=$(tr -d '[:space:]' < versions.txt)
    IFS=. read -r MAJ MIN PAT <<EOF
    $v
    EOF
    printf '%s.%s.0\n' "$MAJ" "$((MIN + 1))" > versions.txt
    cat versions.txt

bump-major:
    #!/usr/bin/env sh
    set -eu
    v=$(tr -d '[:space:]' < versions.txt)
    IFS=. read -r MAJ MIN PAT <<EOF
    $v
    EOF
    printf '%s.0.0\n' "$((MAJ + 1))" > versions.txt
    cat versions.txt
```

Cutting a new version: `just bump-patch` (or `bump-minor` / `bump-major`) → commit `versions.txt` →
merge into the `main` / `master` branch. The workflow creates the tag and the release.

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
`gitea-release`, `local` or `go-install`.

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

In CI no normalisation is needed: `${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}` is already canonical.
The release workflows from this repository build the value that way.

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

### Idempotent CI release

The workflow must check whether the tag exists and skip the build if it already does. This makes
pushing to `master` again safe.

### Reusable workflow

Use the template from this repository — it already implements all the conventions: computing the
executable name (from the repository name), building for four platforms, generating `SHA256SUMS`,
idempotency.

- GitHub Actions: `workflows/release.yml` → `.github/workflows/release.yml`
- Gitea Actions: `workflows/release-gitea.yml` → `.gitea/workflows/release.yml`

The templates are interchangeable: the archive names, `SHA256SUMS` and the `vX.Y.Z` tag format are
identical, so a release from either platform is installed by the very same `github_install.sh`. The
Gitea template uses no external actions (checkout, installing Go and publishing the release are
shell `run:` steps, the release is created through the Gitea API), so it also works where the
runner cannot download actions from github.com.
