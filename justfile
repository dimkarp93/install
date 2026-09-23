_default:
    @just --list

sync-workflows:
    #!/usr/bin/env sh
    set -eu
    ./init_install.sh --emit workflow-go-github > workflows/release.yml
    ./init_install.sh --emit workflow-go-gitea  > workflows/release-gitea.yml
    ./init_install.sh --emit workflow-sh-github > workflows/release-sh.yml
    ./init_install.sh --emit workflow-sh-gitea  > workflows/release-sh-gitea.yml
    ./init_install.sh --emit workflow-go-gitlab > workflows/release-gitlab.yml
    ./init_install.sh --emit workflow-sh-gitlab > workflows/release-sh-gitlab.yml
    echo "Synced: workflows/"

check:
    #!/usr/bin/env sh
    set -eu
    for f in *.sh; do sh -n "$f"; done
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    for pair in workflow-go-github:release.yml workflow-go-gitea:release-gitea.yml \
                workflow-sh-github:release-sh.yml workflow-sh-gitea:release-sh-gitea.yml \
                workflow-go-gitlab:release-gitlab.yml workflow-sh-gitlab:release-sh-gitlab.yml; do
        t=${pair%%:*}
        f=${pair#*:}
        ./init_install.sh --emit "$t" > "$tmp/$f"
        if ! diff -u "workflows/$f" "$tmp/$f"; then
            echo "workflows/$f is out of sync with 'init_install.sh --emit $t' - run: just sync-workflows" >&2
            exit 1
        fi
    done
    echo "OK: the scripts parse and workflows/ matches the templates"

smoke:
    #!/usr/bin/env sh
    set -eu
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    ./init_install.sh --lang go --owner dimkarp93 --ci all --no-git "$tmp/smokego" >/dev/null
    ./init_install.sh --lang sh --ci github,gitlab --no-git "$tmp/smokesh" >/dev/null
    (cd "$tmp/smokego" && git init -q && git add -A && git -c user.email=smoke@local -c user.name=smoke commit -qm init && just build >/dev/null)
    (cd "$tmp/smokesh" && git init -q && git add -A && git -c user.email=smoke@local -c user.name=smoke commit -qm init && just build >/dev/null)
    ./check_install.sh --build "$tmp/smokego"
    ./check_install.sh --build "$tmp/smokesh"
