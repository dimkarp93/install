# install

*Languages: **English** · [Русский](README.ru.md)*

A universal installer for programs published in GitHub and Gitea Releases, plus a CI release template.

The program may be written in any language — the installers only care about a ready-made executable
and about following the [conventions](CONVENTIONS.en.md). There is also a separate `go_install.sh` —
an optional installer for Go programs on top of the standard `go install`, for those who already
have Go installed.

## Installing the installers into PATH

To avoid typing a long `curl` command every time, install the installers
(`github_install.sh`, `gitea_install.sh`, `local_install.sh`, `go_install.sh` and
`check_install.sh`) into PATH once:

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
first tries `<module>/cmd/<name>` (the recommended layout) and then the module root. The
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

## Checking conformance to the conventions (`check_install.sh`)

`check_install.sh` verifies that a repository follows [CONVENTIONS.en.md](CONVENTIONS.en.md):
the presence of `.git`, a valid `versions.txt`, the executable name (from the directory name),
the build target, the `bump-*` targets, the release workflow, the git tag format and the origin
(a valid `upstream.txt` if present, and `-X main.origin` in the build target and in the release
workflow). The arguments
are the same as for `local_install.sh` (the default path is the current directory, a relative path
is looked up in the roots from `~/.config/install/roots.txt`).

```sh
check_install.sh                 # current directory
check_install.sh myapp           # by name (looked up in the roots)
check_install.sh ~/dev/myapp     # by absolute path
```

The `--build` flag additionally builds the executable and checks its output: that `--version` prints
the version from `versions.txt`, and that `--origin` prints one canonical URL (or `local`) with no
credentials in it:

```sh
check_install.sh --build myapp
```

The origin checks are `[WARN]` without `--build` — the migration of the existing tools is not
finished yet, so a missing `-X main.origin` does not fail the check. With `--build` a broken or
missing `--origin` is a `[FAIL]`.

Every check is marked `[OK]` / `[WARN]` / `[FAIL]`. Exit code `0` means all required checks passed,
`1` means there are errors (warnings do not affect the exit code).

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

The `workflows/` directory holds two equivalent templates — pick one by platform:

| Platform | Template | Where to copy it |
|---|---|---|
| GitHub Actions | `workflows/release.yml` | `.github/workflows/release.yml` |
| Gitea Actions | `workflows/release-gitea.yml` | `.gitea/workflows/release.yml` |

Both workflows do the same thing:

- read the version from `versions.txt`,
- derive the executable name from the repository name,
- build static executables for four platforms,
- generate `SHA256SUMS`,
- create a release with a `vX.Y.Z` tag,
- skip the build if the tag already exists (idempotent).

The archive names, `SHA256SUMS` and the tag format are identical on both platforms. A GitHub
release is installed with `github_install.sh`, a Gitea release with `gitea_install.sh` (with the
`-s` flag, see [Installing from Gitea](#installing-from-gitea-gitea_installsh)); they differ only
in the API and download addresses, the flag set is the same.

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
