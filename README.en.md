# install

*Languages: **English** · [Русский](README.ru.md)*

A universal installer for programs published in GitHub, GitLab and Gitea Releases, plus CI release templates.

The program may be written in any language — the installers only care about a ready-made executable
and about following the [conventions](CONVENTIONS.en.md). There is also a separate `go_install.sh` —
an optional installer for Go programs on top of the standard `go install`, for those who already
have Go installed.

## Installing the installers into PATH

To avoid typing a long `curl` command every time, install the installers
(`github_install.sh`, `gitlab_install.sh`, `gitea_install.sh`, `local_install.sh`, `go_install.sh`,
`check_install.sh` and `init_install.sh`) into PATH once:

```sh
curl -fsSL https://raw.githubusercontent.com/dimkarp93/install/master/bootstrap.sh | sh
```

There is no need to clone the repository. `bootstrap.sh` downloads the current installers from
master itself and puts them into `/usr/local/bin` (using `sudo` if required). To install into
`~/.local/bin` without `sudo`, add `--user-only`:

```sh
curl -fsSL https://raw.githubusercontent.com/dimkarp93/install/master/bootstrap.sh | sh -s -- --user-only
```

After that, installing any program looks like this:

```sh
github_install.sh owner/repo
```

### Installing from a working copy (`dev-bootstrap.sh`)

If you are editing the installers themselves, `dev-bootstrap.sh` installs them from the current
working copy of this repository instead of GitHub. Run it from the directory with the sources:

```sh
./dev-bootstrap.sh             # into /usr/local/bin
./dev-bootstrap.sh --user-only # into ~/.local/bin
```

## Installing programs via curl (without `github_install.sh`)

If you do not want to install `github_install.sh`, use the `curl` command directly:

```sh
curl -fsSL https://raw.githubusercontent.com/dimkarp93/install/master/github_install.sh \
  | sh -s -- owner/repo
```

The script:
1. Detects the OS and the architecture.
2. Downloads the archive of the latest version and the `SHA256SUMS` file.
3. Verifies the archive checksum.
4. Extracts and installs the executable into `/usr/local/bin` (or into `~/.local/bin`
   with `--user-only`; uses `sudo` if required).

### Installation directory

By default the executable is installed into `/usr/local/bin`. With the `--user-only` flag it goes
into `~/.local/bin` (without `sudo`):

```sh
github_install.sh --user-only owner/repo
```

### Installing a specific version

```sh
github_install.sh owner/repo myapp 0.3.0
# or via curl:
curl -fsSL .../github_install.sh | sh -s -- owner/repo myapp 0.3.0
```

### Interactive version selection

```sh
github_install.sh -i owner/repo
```

### List of available versions

```sh
github_install.sh --list owner/repo
```

### Downloading the archive without installing

The `-D` / `--download` flag downloads the archive and `SHA256SUMS`, verifies the checksum and
prints the full path to the archive. No installation is performed.

```sh
github_install.sh -D owner/repo
```

The files are saved into the current directory. On success only the archive path is printed to
standard output (suitable for use in scripts):

```
/tmp/downloads/myapp-linux-amd64.tar.gz
```

### Installing from a local archive

The `-F` / `--from-file` flag installs the program from an already downloaded archive. The
`SHA256SUMS` file must be located next to the archive. The version argument and the `-i` and `-u`
flags are ignored.

```sh
github_install.sh -F /tmp/downloads/myapp-linux-amd64.tar.gz
```

This is a direct replacement for the two-step installation — download, then install:

```sh
ARCHIVE=$(github_install.sh -D owner/repo)
github_install.sh -F "$ARCHIVE"
```

The two-step variant is useful when you need to inspect the archive manually between downloading
and installing, or to install the same build on several machines without downloading it again.

### Private repositories

To install from a private repository, pass a GitHub token with the `contents: read` permission:

```sh
GITHUB_TOKEN=ghp_... github_install.sh owner/private-repo
```

The token is used both for GitHub API requests (fetching the release list) and for downloading the
archive and `SHA256SUMS`. A private repository is not reachable without a token.

### GitHub API rate limit

By default the GitHub API allows 60 unauthenticated requests per hour. If you use it often, pass a
token:

```sh
GITHUB_TOKEN=ghp_... github_install.sh owner/repo
```

### Other GitHub instances (`GITHUB_URL`)

By default the script works with the public `https://github.com`. To install from another instance
(GitHub Enterprise Server, a mirror), set its address with the `-s` / `--server` flag or the
`GITHUB_URL` environment variable (the flag wins; the scheme may be omitted):

```sh
GITHUB_URL=https://github.example.com github_install.sh owner/repo
github_install.sh -s github.example.com owner/repo
```

The API address is derived from it: `https://api.github.com` for `github.com`, `<GITHUB_URL>/api/v3`
for any other instance. If the API lives elsewhere, set `GITHUB_API_URL`. The messages print the
resulting URLs, so it is visible where the installation came from.

## Installing from Gitea (`gitea_install.sh`)

`gitea_install.sh` installs a program from the releases of a self-hosted Gitea — for example those
built by the `workflows/release-gitea.yml` template. The script does exactly the same as
`github_install.sh` (detects the OS and architecture, downloads the archive and `SHA256SUMS`,
verifies the checksum, extracts and installs the executable) and understands the same flags. The
release requirements are the same as for GitHub: `<name>-<os>-<arch>.tar.gz` archives, a
`SHA256SUMS` file, `vX.Y.Z` tags (see [CONVENTIONS.en.md](CONVENTIONS.en.md)).

There is a single difference: the Gitea instance address is mandatory — the `-s` / `--server` flag.

```sh
gitea_install.sh -s https://git.example.com owner/repo
```

The scheme may be omitted — `https://` is substituted:

```sh
gitea_install.sh -s git.example.com owner/repo
```

Instead of the flag, the address can be set through the `GITEA_URL` environment variable:

```sh
export GITEA_URL=https://git.example.com
gitea_install.sh owner/repo
```

Via `curl`, without installing the script:

```sh
curl -fsSL https://raw.githubusercontent.com/dimkarp93/install/master/gitea_install.sh \
  | sh -s -- -s https://git.example.com owner/repo
```

### The remaining flags

They work the same way as in `github_install.sh` (see the sections above): `-i` — interactive
version selection, `--list` — the version list, `-u` — update only if a newer version exists,
`-D` — only download the archive with checksum verification, `-F` — install from a local archive,
`--user-only` — install into `~/.local/bin`. The positional arguments are the same:
`<owner/repository> [binary-name] [version]`.

```sh
gitea_install.sh -s https://git.example.com --list owner/repo
gitea_install.sh -s https://git.example.com -i --user-only owner/repo
gitea_install.sh -s https://git.example.com owner/repo myapp 0.3.0
```

The `-F` flag does not need the server address — the network is not used:

```sh
ARCHIVE=$(gitea_install.sh -s https://git.example.com -D owner/repo)
gitea_install.sh -F "$ARCHIVE"
```

### Private repositories

Installing from a private repository works — a Gitea token is required. To obtain one:
_Settings → Applications → Generate New Token_, scope `read:repository` (that is enough, `write` is
not needed). The token is passed in the `GITEA_TOKEN` variable:

```sh
GITEA_TOKEN=... gitea_install.sh -s https://git.example.com owner/private-repo
```

The token is added to every request: both to the Gitea API (`/api/v1/repos/...` — the release list,
asset lookup) and to downloading the archive and `SHA256SUMS`. It works with all flags, including
`-D`, `-i` and `--list`:

```sh
export GITEA_URL=https://git.example.com
export GITEA_TOKEN=...
gitea_install.sh --list owner/private-repo
gitea_install.sh -u owner/private-repo
```

The links to the archive and `SHA256SUMS` are not assembled by hand but taken from the API response
(the asset `browser_download_url`) — so the installation does not break if the instance serves
attachments from a non-standard path or from external storage.

Without a token a private repository is unreachable: Gitea answers `401`/`404`, and the script
suggests setting `GITEA_TOKEN`. Public repositories do not need a token.

## Installing from GitLab (`gitlab_install.sh`)

`gitlab_install.sh` installs a program from GitLab Releases — for example those built by the
`workflows/release-gitlab.yml` template. It understands the same flags as `gitea_install.sh`
(`-s`, `-i`, `--list`, `-u`, `-D`, `-F`, `--user-only`) and the same positional arguments:
`<namespace/project> [binary-name] [version]`; the namespace may be nested (`group/subgroup/project`).

The instance is taken from `-s` / `--server`, then from `GITLAB_URL`, and defaults to
`https://gitlab.com`:

```sh
gitlab_install.sh dimkarp93/kdbx-cli
gitlab_install.sh --list dimkarp93/kdbx-cli
GITLAB_URL=https://gitlab.example.com gitlab_install.sh group/tool
```

Via `curl`, without installing the script:

```sh
curl -fsSL https://raw.githubusercontent.com/dimkarp93/install/master/gitlab_install.sh \
  | sh -s -- dimkarp93/kdbx-cli
```

The release is read through the API (`/api/v4/projects/<namespace%2Fproject>/releases`); the archive
and `SHA256SUMS` are the release links (`assets.links`) with the matching names — the script
downloads them by `direct_asset_url`. For a private project pass a token with the `read_api` scope in
`GITLAB_TOKEN`: it is sent as the `PRIVATE-TOKEN` header both to the API and to the downloads.

```sh
GITLAB_TOKEN=glpat-... gitlab_install.sh group/private-tool
```

## Installing Go programs via `go install` (`go_install.sh`)

`go_install.sh` is an optional alternative for those who already have Go installed.
It does not download release archives; it builds the program with the standard `go install`
straight from the module sources and puts the executable into PATH.

```sh
go_install.sh github.com/dimkarp93/md-pdf
go_install.sh --user-only github.com/dimkarp93/md-pdf
go_install.sh github.com/dimkarp93/md-pdf 0.3.0
go_install.sh --list github.com/dimkarp93/md-pdf
```

No release, archives or `SHA256SUMS` are needed here — the version comes from the repository git
tag, and the integrity of public modules is verified by `sum.golang.org`.

`go_install.sh` always installs from the public `github.com` through the standard Go module
mechanism. `GITHUB_URL` / `GITLAB_URL` are not used: `go install` finds a module by its path, not by a
URL. If `GITHUB_URL` points at another instance, the script prints a warning and carries on as usual.
To install from a mirror, use `github_install.sh` / `gitlab_install.sh`.

### When to use it and when not to

Use `go_install.sh` if Go is already installed, the program is written in Go and its module follows
the [Go conventions](CONVENTIONS.en.md#go-programs-requirements-for-go-install-optional).

Use `github_install.sh` / `gitea_install.sh` if:

- there is no Go on the machine (the release installers install a prebuilt binary and do not
  require Go);
- the program is not written in Go;
- the machine is in an isolated network: module dependencies are fetched from `proxy.golang.org` or
  directly from github.com, whereas the release installer only needs access to the Gitea instance
  itself.

The `-D`, `-F`, `-i`, `-u` flags are not supported: `go install` has no intermediate archive, which
these scenarios are built around. Use `github_install.sh` or `gitea_install.sh` for them.

### Detecting the package and the binary name

`go install` derives the executable name from the last segment of the package path. The script
first tries `<module>/cmd/<name>` (the layout required by the conventions) and then the module root
(for third-party modules). The
major-version suffix (`/v2`, `/v3`) is dropped when computing the name. The package path can be set
explicitly:

```sh
go_install.sh -p golang.org/x/tools/cmd/stringer golang.org/x/tools
```

### Installation directory

By default it is `/usr/local/bin` (using `sudo` if required), with `--user-only` it is
`~/.local/bin`. The `--gobin` flag leaves the binary where `go install` itself puts it
(`$GOBIN`, `~/go/bin` by default).

### Private repositories

The `proxy.golang.org` proxy does not serve private modules, so `go` must be told to go to git
directly and the access must be configured:

```sh
export GOPRIVATE='github.com/dimkarp93/*'
go_install.sh github.com/dimkarp93/md-pdf
```

Git access is configured the usual way — an SSH key or `~/.netrc`. The `GITHUB_TOKEN` /
`GITEA_TOKEN` tokens are not used here: only `github_install.sh` and `gitea_install.sh` understand
them.

For a module in Gitea the module path must start with the instance address
(`module git.example.com/owner/repo`), and `GOPRIVATE` must include that host. If Gitea is only
reachable over SSH on a non-standard port, add a substitution:

```sh
git config --global url."ssh://git@git.example.com:2222/".insteadOf "https://git.example.com/"
export GOPRIVATE='git.example.com/*'
go_install.sh git.example.com/owner/repo
```

## Local installation from sources (`local_install.sh`)

`local_install.sh` installs a program straight from a git repository working copy — without
publishing a GitHub Release. This is handy during development: edit the code, install locally,
check — with no release cut.

The executable name is taken from the repository directory name. There is no need to analyse the
workflow file any more.

### Configuring the roots

The script looks for programs in the list of root directories from `~/.config/install/roots.txt`:
one directory per line, `#` comments and empty lines are ignored, `~` expands to the home directory
of the current user. If the file is missing or empty, the only default root is `~/tools`.

```
# ~/.config/install/roots.txt
~/tools
~/dev
```

### Usage examples

Install the program from the current directory (no path given):

```sh
cd ~/dev/myapp
local_install.sh
```

By name (looked up in the roots):

```sh
local_install.sh myapp
```

By absolute path:

```sh
local_install.sh ~/dev/myapp
```

Into `~/.local/bin` without `sudo`:

```sh
local_install.sh --user-only myapp
```

### Repository requirements

In addition to the standard requirements from [CONVENTIONS.en.md](CONVENTIONS.en.md), a local
installation needs:

- **A build target**: `just build` (Justfile) or `make build` (Makefile).
- **The executable in the root**: the build target must put the executable `<name>` right into the
  repository root.
- **The executable name**: matches the directory name.

## Creating a new program (`init_install.sh`)

`init_install.sh` creates a repository that already follows
[CONVENTIONS.en.md](CONVENTIONS.en.md) — one command instead of copying the templates by hand:

```sh
init_install.sh --lang go --owner dimkarp93 mytool   # ./mytool in the current directory
init_install.sh --lang sh ~/dev/mytool               # by absolute path
```

What ends up in the repository:

| File | Purpose |
|---|---|
| `versions.txt` | `0.1.0` — the source of truth for the version |
| `justfile` | `build`, `check`, `bump-patch/minor/major`, `release`, `install`, `clean` |
| `.gitignore` | the executable built in the root, `dist/` |
| `cmd/<name>/main.go` or `<name>.sh` | the skeleton with `--version` / `--origin` / `--buildinfo` |
| `go.mod` | `module <host>/<owner>/<name>` (for `--lang go`) |
| `.github/workflows/release.yml` | the GitHub release workflow |
| `.gitlab-ci.yml`, `.gitea/workflows/release.yml` | the GitLab / Gitea release workflows (with `--ci gitlab` / `--ci gitea`) |
| `vendor/`, `.gitattributes` | vendored dependencies (for `--lang go`); the `justfile` exports `GOWORK=off` / `GOFLAGS=-mod=vendor` and has the `vendor` / `vendor-check` recipes |
| `README.md` | how to install, build and release |

For `--lang go` the skeleton uses
[`install-libs/buildinfo`](https://github.com/dimkarp93/install-libs), so the three flags are
implemented by the library rather than by hand; `init_install.sh` fetches the dependency itself.
For `--lang sh` the `VERSION` / `ORIGIN` / `UPSTREAM` / `COMMIT` / `CHANNEL` values are substituted
into the script by the `build` recipe and by the workflow.

The flags:

```
--lang go|sh                  language of the skeleton (default: go)
--owner OWNER                 repository owner (required for --lang go)
--host HOST                   repository host (default: github.com)
--upstream URL                write upstream.txt (for mirrors)
--ci LIST                     release workflows: a comma-separated list of github, gitea,
                              gitlab; or all, none (default: github)
--remote URL                  git remote add origin URL
--no-git                      do not run git init and do not create the first commit
--force                       fill an existing directory (existing files are kept)
--emit TEMPLATE               print a template to stdout and exit

<name|path>                   an absolute path, or a name or relative path -
                              resolved against the current directory
```

No existing file is ever overwritten: a file that is already there is reported as `[skip]`. That
makes it safe to run the command over a half-finished repository with `--force`. At the end
`init_install.sh` runs `check_install.sh` over the result, so the output immediately shows whether
the repository conforms.

Releasing the program afterwards is one command too:

```sh
just release patch    # bump versions.txt -> commit -> push; the tag and the release are made by the workflow
```

`--emit` prints a template without creating anything — it is the single source of the templates:
the files in `workflows/` are generated from it (`just sync-workflows`), and `check_install.sh
--fix` takes what it adds from the same place.

## Checking conformance to the conventions (`check_install.sh`)

`check_install.sh` verifies that a repository follows [CONVENTIONS.en.md](CONVENTIONS.en.md):
the presence of `.git`, a valid `versions.txt`, the executable name (from the directory name),
the build target, the `bump-*` targets, the release workflow (including `SHA256SUMS` and the
per-platform archives), the git tag format, `versions.txt` against the latest tag, the executable
in `.gitignore` and the origin (a valid `upstream.txt` if present, and the origin embedded by the
build target and by the release workflow). If there is a `go.mod`, the requirements of the
`go install` section are checked as well: a network module path, its last segment against the
binary name, the `/vN` suffix for major versions from `2.0.0` on, the absence of `replace` and the
location of `package main` (only `cmd/<name>/`, none in the module root), and the mandatory vendoring: `vendor/modules.txt` when `go.mod` has
dependencies, `vendor/` not ignored, the `GOWORK=off` / `GOFLAGS=-mod=vendor` exports in the build
file, the `vendor-check` recipe (a missing `.gitattributes` line or a leftover `go.work` is a
warning). A GitHub / GitLab release workflow without the
guard on its public domain (`github.server_url == 'https://github.com'`,
`$CI_SERVER_HOST == "gitlab.com"`) is a `[FAIL]`. The argument is a path to the repository: an absolute path, or a name
or relative path resolved against the current directory. If no path is given, the current directory
is used.

```sh
check_install.sh                 # current directory
check_install.sh myapp           # ./myapp in the current directory
check_install.sh ~/dev/myapp     # by absolute path
```

The `--build` flag additionally builds the executable and checks its output: that `--version` prints
the version from `versions.txt`, and that `--origin` prints one canonical URL (or `local`) with no
credentials in it. For a Go module with dependencies it also runs `GOWORK=off go list -mod=vendor ./...`, which fails
on inconsistent vendoring without touching the working copy:

```sh
check_install.sh --build myapp
```

The origin checks are `[WARN]` without `--build` — the migration of the existing tools is not
finished yet, so a missing `-X main.origin` does not fail the check. With `--build` a broken or
missing `--origin` is a `[FAIL]`.

Every check is marked `[OK]` / `[WARN]` / `[FAIL]`. Exit code `0` means all required checks passed,
`1` means there are errors (warnings do not affect the exit code).

### Fixing what is missing (`--fix`)

The `--fix` flag creates the missing pieces before checking, and only them — nothing that is
already in the repository is overwritten, so the flag is idempotent:

```sh
check_install.sh --fix myapp
```

- no `versions.txt` → created with `0.1.0`;
- no `.gitignore`, or no executable in it → created or extended with `/<name>` and `/dist/`;
- no `bump-*` recipes in the `justfile` → appended to the end;
- no release workflow at all → `.github/workflows/release.yml` is added (the Go or the shell
  variant, depending on whether there is a `go.mod`);
- Go module with dependencies and no `vendor/` → `GOWORK=off go mod vendor`;
- `vendor/` is present → `vendor/** linguist-generated=true -diff` is added to `.gitattributes`;
- Go and a `justfile` → the `export GOWORK/GOFLAGS` lines and the `vendor` / `vendor-check` recipes
  are appended if missing (a `Makefile` only gets a hint).

An existing workflow is never overwritten: if it has no domain guard, regenerate it with
`init_install.sh --emit workflow-go-github` (or `-sh-`, `-gitlab`).

A `Makefile` is not edited automatically: the syntax of the targets differs, so `--fix` only says
that the `bump-*` targets have to be added by hand (there is a ready block in
[CONVENTIONS.en.md](CONVENTIONS.en.md)).

The templates come from `init_install.sh --emit`, so `--fix` needs `init_install.sh` in PATH or
next to `check_install.sh`; both are installed by `bootstrap.sh`.

## Updating

Updating is simply reinstalling: the executable in PATH is overwritten. The script determines the
latest version and installs it:

```sh
github_install.sh owner/repo
```

To update only when a newer version is available:

```sh
github_install.sh -u owner/repo
```

### Which mirror is this binary from

The same program can be installed from an upstream on GitHub or from a mirror in Gitea. The
installed executable reports the repository it was built from itself:

```sh
$ mytool --origin
https://gitea.example.org/dima/mytool

$ mytool --buildinfo
origin=https://gitea.example.org/dima/mytool
upstream=https://github.com/dimkarp93/mytool
version=0.4.0
commit=431b60b
channel=gitea-release
```

The value is self-declared and is meant for diagnostics — it does not prove where the executable
really came from and must not be used as a basis for trust. See the "Origin" section of
[CONVENTIONS.en.md](CONVENTIONS.en.md).

## Requirements for programs

To be installable with the installers from this repository, a program must:

1. **Be published on GitHub** with tags shaped like `vMAJOR.MINOR.PATCH`.
2. **Have a `versions.txt`** in the repository root holding the version in semver format (`0.4.0`).
3. **Have an executable name** equal to the repository name.
4. **Attach archives to the release** named `<name>-<os>-<arch>.tar.gz` for the
   `linux/amd64`, `linux/arm64`, `darwin/amd64`, `darwin/arm64` platforms.
5. **Attach a `SHA256SUMS`** — the output of `sha256sum *.tar.gz`.
6. **Put the executable `<name>`** into the archive root (or into the
   `<name>-<os>-<arch>/` directory).
7. **Print the version in semver format** for `--version` (just the `0.4.0` string, with no spaces
   or extra text).
8. **Print the source repository** for `--origin` — a single line with the canonical URL of the
   repository the executable was built from — and the rest of the build attributes for
   `--buildinfo`, as `key=value` lines.

The full description of the requirements is in [CONVENTIONS.en.md](CONVENTIONS.en.md).

## Using the CI release template

The `workflows/` directory holds six equivalent templates — pick one by platform and by the
language of the program (`init_install.sh` puts the right one in place by itself):

| Platform | Go | POSIX shell | Where to copy it |
|---|---|---|---|
| GitHub Actions | `workflows/release.yml` | `workflows/release-sh.yml` | `.github/workflows/release.yml` |
| GitLab CI | `workflows/release-gitlab.yml` | `workflows/release-sh-gitlab.yml` | `.gitlab-ci.yml` |
| Gitea Actions | `workflows/release-gitea.yml` | `workflows/release-sh-gitea.yml` | `.gitea/workflows/release.yml` |

The shell templates build the executable by substituting the version and the origin into
`<name>.sh` (or `<name>-init.sh`) with `sed` instead of calling `go build`, and they check the
source with `sh -n`; everything else — the archive names, `SHA256SUMS`, the tag, the idempotency —
is identical.

The files in `workflows/` are generated from the templates embedded into `init_install.sh`:
`just sync-workflows` refreshes them, `just check` fails if they have drifted apart.

All the workflows do the same thing:

- read the version from `versions.txt`,
- derive the executable name from the repository name,
- build static executables for four platforms,
- generate `SHA256SUMS`,
- create a release with a `vX.Y.Z` tag,
- skip the build if the tag (GitLab: the release) already exists (idempotent),
- check that `go mod vendor` changes nothing (`git status` of `go.mod`, `go.sum`, `vendor/`); the
  build runs with `GOWORK=off` and `GOFLAGS=-mod=vendor`, i.e. from `vendor/` only.

The GitHub template runs only on `github.com` (`if: github.server_url == 'https://github.com'`), the
GitLab template only on `gitlab.com` (`$CI_SERVER_HOST == "gitlab.com"`): in mirrors on other
instances the job is skipped. The Gitea templates have no such guard.

The archive names, `SHA256SUMS` and the tag format are identical on all platforms. A GitHub
release is installed with `github_install.sh`, a GitLab release with `gitlab_install.sh`, a Gitea
release with `gitea_install.sh` (with the `-s` flag, see
[Installing from Gitea](#installing-from-gitea-gitea_installsh)); they differ only in the API and
download addresses, the flag set is the same.

Cutting a new version: bump the version (`just bump-patch` / `bump-minor` / `bump-major` — see
[CONVENTIONS.en.md](CONVENTIONS.en.md)), commit `versions.txt` and merge into the `main` / `master`
branch.

### Specifics of the Gitea template

`workflows/release-gitea.yml` uses no external actions at all: `actions/checkout` and
`actions/setup-go` are replaced with `run:` (shell) steps, and `gh release create` with Gitea API
calls through `curl`. This is needed because Gitea pulls actions from github.com, and they are
unavailable in an isolated network. In practice this means:

- **Checkout** — `git init` plus a shallow fetch of the `$GITHUB_SHA` commit from
  `$GITHUB_SERVER_URL`.
- **Go** — the version is read from `go.mod` (the `toolchain` directive, otherwise `go`); if only
  `X.Y` is specified, the exact patch is resolved through `https://go.dev/dl/?mode=json`. The
  tarball is installed into `$HOME/.local/go` (no root required). The runner needs access to
  `go.dev`.
- **Release** — `POST /api/v1/repos/{owner}/{repo}/releases`: Gitea creates the tag from
  `target_commitish` itself, no separate `git push --tags` is needed. Then the archives and
  `SHA256SUMS` are uploaded as assets.
- **Token** — `secrets.GITHUB_TOKEN`, which Gitea issues to every job automatically; there is no
  need to create a secret by hand. If the API answers `403`, enable write access for the Actions
  token in the repository settings or substitute your own token with the `write:repository` scope.
- **`runs-on: ubuntu-latest`** — this is a runner label. If your `act_runner` is registered with
  different labels, adjust `runs-on` accordingly.

### Specifics of the GitLab template

`workflows/release-gitlab.yml` (→ `.gitlab-ci.yml`) is a single `release` job:

- **Trigger** — a push to the default branch on `gitlab.com`. The job reads `versions.txt` and exits
  if the `vX.Y.Z` release already exists, so it works both when GitLab is the main platform and when
  it is a mirror whose tags arrive from GitHub.
- **Image** — `golang:1` for Go (`GOTOOLCHAIN=auto` fetches the version from `go.mod`), `alpine:3`
  with `curl` for shell programs.
- **Build** — the same four platforms, archive names, `-ldflags` and `SHA256SUMS` as on GitHub;
  `origin` is `$CI_PROJECT_URL`, `channel` is `gitlab-release`.
- **Publishing** — the files are uploaded into the project's generic package registry
  (`/packages/generic/<name>/<version>/<file>`), then `POST /releases` with `ref=$CI_COMMIT_SHA`
  creates the release (and the tag, if it does not exist yet) with release links to the files.
- **Token** — `CI_JOB_TOKEN`, nothing needs to be configured.
