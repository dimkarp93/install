# Требования к программам для установки

*Языки: **Русский** · [English](CONVENTIONS.en.md)*

Чтобы программу можно было установить и обновить через установщики этого репозитория —
как из GitHub / GitLab / Gitea Releases (`github_install.sh`, `gitlab_install.sh`,
`gitea_install.sh`), так и локально из рабочей копии (`local_install.sh`) — она должна
удовлетворять описанным ниже требованиям.

Программа может быть написана на любом языке: установщикам важны лишь готовый исполняемый
файл и соблюдение конвенций об именах, архивах и версиях.

## Общие требования

### 1. Имя исполняемого файла

Имя исполняемого файла совпадает с именем каталога репозитория (оно же — имя репозитория
на GitHub, последний сегмент `owner/NAME`). Установщики и workflow релиза выводят имя
исполняемого файла из имени каталога (репозитория): каталог `<имя>` → исполняемый файл
`<имя>`.

Если программа обязана называться иначе (например, git remote helper обязан называться
`git-remote-<транспорт>`, чтобы git нашёл его в `PATH`), репозиторий следует назвать так
же, как исполняемый файл.

### 2. Имена файлов в релизе

К релизу приложены архивы для всех поддерживаемых платформ:

```
<имя>-linux-amd64.tar.gz
<имя>-linux-arm64.tar.gz
<имя>-darwin-amd64.tar.gz
<имя>-darwin-arm64.tar.gz
```

Здесь `<имя>` — имя исполняемого файла (см. п. 1).

### 3. Файл SHA256SUMS

К тому же релизу приложён файл `SHA256SUMS` — вывод команды `sha256sum *.tar.gz`.
Установщик проверяет целостность архива по этому файлу перед распаковкой.

### 4. Структура архива

Исполняемый файл `<имя>` находится в одном из двух мест внутри архива:

- в корне: `<имя>`
- в каталоге с именем платформы: `<имя>-<os>-<arch>/<имя>`

Других обязательных файлов в архиве нет.

### 5. Локальная сборка (для `local_install.sh`)

В репозитории есть цель `just build` (в `Justfile`) **или** `make build` (в `Makefile`),
которая помещает исполняемый файл `<имя>` (см. п. 1) в **корень репозитория**. Go-программа
собирается только из `vendor/` (см. [vendoring](#go-программы-vendoring-обязательно)).
`local_install.sh` использует эту цель для установки программы локально, до публикации
GitHub Release.

```
<корень-репозитория>/<имя>   ← исполняемый файл должен оказаться здесь после just/make build
```

## Go-программы: раскладка (обязательно)

`package main` Go-программы лежит в `cmd/<имя>/`, где `<имя>` — имя исполняемого файла (п. 1 общих
требований); в корне модуля `package main` нет:

```
<корень>/go.mod             module github.com/owner/<имя>
<корень>/cmd/<имя>/main.go  package main
```

Рецепты сборки и release-workflow собирают именно этот пакет (`./cmd/<имя>`). Файлы, которые
программа встраивает через `//go:embed`, лежат рядом с ним, внутри `cmd/<имя>/`. Остальной код —
в `internal/` или других пакетах модуля.

Имя исполняемого файла `go install` берёт из последнего сегмента пути **пакета**, поэтому
`go install github.com/owner/<имя>/cmd/<имя>@vX.Y.Z` даёт бинарь с правильным именем.

## Go-программы: требования для `go install` (необязательно)

Этот раздел применяется, **только если** программу хотят устанавливать через
`go_install.sh` (то есть штатным `go install`). Для установки через
`github_install.sh`, `gitlab_install.sh`, `gitea_install.sh` и `local_install.sh` он не нужен: там
достаточно общих требований выше, и язык программы значения не имеет.

### 1. Module path — сетевой адрес

В `go.mod` путь модуля должен указывать на реальный адрес репозитория:

```
module github.com/<владелец>/<имя>
module <хост-gitea>/<владелец>/<имя>
```

Голое имя (`module secrets`) делает `go install` невозможным: `go` не знает, откуда
качать модуль. Последний сегмент пути модуля совпадает с именем репозитория и именем
исполняемого файла (п. 1 общих требований).

### 2. Зависимости должны быть опубликованы

`go install <пакет>@<версия>` собирает модуль в отрыве от рабочей копии:

- `go.work` **игнорируется** — локальные `replace` из него не применяются;
- `replace` в самом `go.mod` не поддерживается и приводит к ошибке.

Поэтому каждая внутренняя зависимость должна быть опубликована как отдельный модуль с
semver-тегом и присутствовать в `go.sum`. Локальных `replace` тоже нет: чтобы использовать
изменение зависимости, опубликуйте его и обновите vendor (см.
[vendoring](#go-программы-vendoring-обязательно)).

### 3. Major-версии

Начиная с `v2.0.0` путь модуля обязан иметь суффикс с номером major-версии:

```
module github.com/owner/<имя>/v2
```

Иначе `go install <модуль>@v2.0.0` завершится ошибкой. `go_install.sh` учитывает
суффикс при вычислении имени бинаря.

### 4. Версия при `go install`

`versions.txt` остаётся источником истины для релизных workflow и `local_install.sh`.
Но при `go install` сборка идёт без `-ldflags`, которые проставляет workflow, поэтому
`-X main.version` не сработает и `--version` выведет пустую строку.

Чтобы флаг `--version` работал в обоих случаях, берите версию из метаданных модуля,
когда `main.version` не проставлена:

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

Это рекомендация, а не требование: при установке через релизные архивы версия
проставляется workflow как прежде.

## Версии

### Семантический тег релиза

Релизы публикуются через GitHub Releases, GitLab Releases или Gitea Releases. Тег каждого релиза — строго
`vMAJOR.MINOR.PATCH` (например, `v1.2.3`).

### Версия хранится в `versions.txt`

В корне репозитория — файл `versions.txt` с версией в формате semver без префикса `v`
(например, `0.4.0`). Версия встраивается в исполняемый файл при сборке (например, через
`ldflags`).

### Флаг `--version`

Исполняемый файл при запуске с флагом `--version` (или `-v`) выводит в стандартный вывод
строку с версией в формате semver:

```
0.4.0
```

Без префикса `v` и без какого-либо дополнительного текста — только номер версии на
отдельной строке.

### Рецепты повышения версии

Для повышения версии репозиторий предоставляет в `Justfile` (или `Makefile`) цели
`bump-patch`, `bump-minor`, `bump-major`. Каждая из них увеличивает соответствующую
компоненту версии в `versions.txt` (обнуляя младшие компоненты):

- `bump-patch`: `1.2.3` → `1.2.4`
- `bump-minor`: `1.2.3` → `1.3.0`
- `bump-major`: `1.2.3` → `2.0.0`

и сразу публикует её:

1. коммитит только `versions.txt` с сообщением `bump <patch|minor|major>`;
2. ставит тег `vX.Y.Z` (если такой тег уже есть — отказывается и возвращает `versions.txt`);
3. выполняет `git push <remote> HEAD --tags` для каждого remote из `git remote`.

Пример целей для `Justfile`:

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

В `Makefile` те же шаги живут во вспомогательной цели, которую вызывает каждая `bump-*`:

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

Выпуск новой версии — одна команда: `just bump-patch` / `make bump-patch` (или `bump-minor` /
`bump-major`) в `main` / `master`. Запушенный тег запускает workflow релиза.

## Источник сборки

Программа может жить сразу в нескольких репозиториях — upstream на GitHub и одно или несколько
зеркал (например, собственная Gitea). По одному только установленному исполняемому файлу тогда
невозможно понять, откуда он взялся. Чтобы это было видно, репозиторий-источник зашивается в
исполняемый файл во время сборки — рядом с версией.

Зашиваются два значения:

- `origin` — репозиторий, из которого исполняемый файл был фактически собран (зеркало);
- `upstream` — канонический репозиторий проекта (куда заводить issue).

Для программы без зеркал оба значения совпадают.

### 1. Флаг `--origin`

При запуске с флагом `--origin` исполняемый файл печатает в стандартный вывод одну строку с URL
репозитория, из которого он собран:

```
https://gitea.example.org/dima/mytool
```

Без какого-либо дополнительного текста — только URL отдельной строкой, в каноническом виде (см.
пункт 3). Если файл собран из рабочей копии без remote, строка равна литералу `local`.

### 2. Флаг `--buildinfo`

Всё остальное о сборке сообщает отдельный флаг `--buildinfo` — строками `key=value` в фиксированном
порядке:

```
origin=https://gitea.example.org/dima/mytool
upstream=https://github.com/dimkarp93/mytool
version=0.4.0
commit=431b60b
channel=gitea-release
```

Ключи `origin`, `upstream` и `version` печатаются всегда; `commit` и `channel` опускаются, когда
неизвестны. `channel` описывает, как получен исполняемый файл: `github-release`, `gitlab-release`,
`gitea-release`, `local` или `go-install`.

Один флаг держит весь набор, поэтому новые атрибуты сборки не требуют каждый раз нового флага —
только новой строки в выводе.

### 3. Канонический вид URL

Зашиваемый URL должен быть каноническим: схема `https`, без учётных данных, без суффикса `.git`, без
завершающего слеша.

```
https://<хост>/<owner>/<имя>
```

Это **требование**, а не вопрос оформления. `git remote get-url origin` может вернуть
`https://user:token@host/owner/repo.git` или `git@host:owner/repo.git`; зашив такую строку как есть,
можно утащить токен или внутреннее имя хоста в исполняемый файл, который потом попадёт в публичный
релиз. Поэтому URL перед зашиванием нормализуется: учётные данные отбрасываются, ssh-форма
приводится к https.

Сниппет для цели сборки в `Justfile` / `Makefile`:

```sh
u=$(git remote get-url origin 2>/dev/null || true)
case "$u" in
    "")    o=local ;;
    *://*) h=${u#*://}; h=${h#*@}; o="https://${h%.git}" ;;
    *:*)   h=${u#*@};   o="https://$(printf '%s' "${h%.git}" | tr ':' '/')" ;;
    *)     o=local ;;
esac
```

Сниппет сохраняет порт, поэтому ssh-remote на нестандартном порту (`ssh://git@host:2222/o/r`) даёт
`https://host:2222/o/r` — ssh-порт не равен https-порту. Для такого репозитория origin задаётся в
цели сборки явно, а не выводится из remote.

В CI нормализация не нужна: `${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}` (GitHub, Gitea) и
`$CI_PROJECT_URL` (GitLab) уже каноничны. Release-workflow из этого репозитория собирают значение
именно так.

### 4. Файл `upstream.txt`

Канонический репозиторий объявляется необязательным файлом `upstream.txt` в корне репозитория —
одна строка с URL в каноническом виде:

```
https://github.com/dimkarp93/mytool
```

Если файла нет, `upstream` равен `origin`. Заводить файл имеет смысл в зеркалах: там `origin`
указывает на зеркало, а `upstream` продолжает указывать на источник истины.

### 5. Источник сборки при `go install`

Как и с версией (см. раздел про `go install` выше), сборка через `go install` идёт без `-ldflags`,
поэтому `main.origin` остаётся пустым. Module path — это ровно тот репозиторий, из которого модуль
был скачан, поэтому он и служит запасным вариантом:

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

Суффикс мажорной версии (`/v2`, `/v3`) срезается, чтобы URL указывал на репозиторий, а не на module
path.

## Go-программы: vendoring (обязательно)

Go-программа хранит зависимости в `vendor/` и собирается **только** из него — и в release-workflow,
и локально (`just build`, `make build`, `local_install.sh`). Сборка не зависит ни от module proxy,
ни от кэша модулей, ни от соседних рабочих копий, подключённых через `go.work`, поэтому её можно
повторить в изолированной сети.

- Если в `go.mod` есть директивы `require`, в репозитории лежит `vendor/` с `vendor/modules.txt`,
  совпадающий с результатом `GOWORK=off go mod vendor`. Модулю без зависимостей `vendor/` не нужен.
- `vendor/` не входит в `.gitignore`; в `.gitattributes` — `vendor/** linguist-generated=true -diff`.
- Файл сборки экспортирует `GOWORK=off` и `GOFLAGS=-mod=vendor`, чтобы все рецепты (`build`, `test`,
  `vet`, `install`, ...) работали только с `vendor/`:

  ```just
  export GOWORK := "off"
  export GOFLAGS := "-mod=vendor"
  ```

  ```make
  export GOWORK := off
  export GOFLAGS := -mod=vendor
  ```

  `go.work` не используется: в репозитории его нет, а `GOWORK=off` ещё и защищает сборку от
  `go.work` в родительском каталоге (Go ищет его вверх по дереву). Чтобы использовать изменение
  зависимости, опубликуйте его и запустите `just vendor`.
- Форматирование не должно трогать `vendor/`: используйте `go fmt ./...`, а не `gofmt -w .`.
- В файле сборки есть рецепты `vendor` и `vendor-check`. `vendor-check` смотрит в `git status`, а не
  только в `git diff`, чтобы ловить и файлы, которых не хватает в закоммиченном `vendor/`:

```just
vendor:
    GOWORK=off go mod tidy
    GOWORK=off go mod vendor

vendor-check:
    GOWORK=off go mod vendor
    test -z "$(git status --porcelain -- go.mod go.sum vendor/ | tee /dev/stderr)"
```

После `go get` запустите `just vendor`: иначе сборка упадёт с «inconsistent vendoring». Release-
workflow выполняют ту же проверку перед сборкой (`GOWORK=off`, `GOFLAGS=-mod=vendor`), а
`check_install.sh` считает ошибкой репозиторий, не соблюдающий этот раздел.

Vendor не отменяет требований раздела про `go install`: `go install` игнорирует `vendor/`,
поэтому зависимости по-прежнему публикуются как модули с semver-тегами. Код в `vendor/`
распространяется вместе с репозиторием — лицензии зависимостей должны это позволять.

## Go-программы: конфиг, окружение, автодополнение (install-libs)

Обязательно для новых Go-программ и целевое состояние для существующих. Механизмы лежат в
пакетах [`install-libs`](https://github.com/dimkarp93/install-libs) начиная с `v0.3.0`;
конкретные значения (имя приложения, префикс переменных, дерево команд) остаются в программе.

- **Путь к конфигу** — только через `install-libs/xdgpath`: `ConfigDir(app)` учитывает
  `XDG_CONFIG_HOME` и по умолчанию даёт `~/.config/<app>`, `ExpandHome` раскрывает `~` в
  пользовательском вводе, `Resolve` применяет явный override (`--config`). Программа, которая
  раньше жёстко читала `~/.config/<app>`, оборачивает путь в `WithLegacy`, чтобы старый файл
  продолжал читаться. Своих `os.Getenv("XDG_CONFIG_HOME")` и `filepath.Join(home, ".config")` в
  коде нет.
- **Опции, которые имеет смысл переопределять через окружение** (сетевые настройки, таймауты,
  режимы), — через `install-libs/envflag`: приоритет `флаг > переменная > значение по умолчанию`,
  у каждой переменной общий префикс (`NET_`, `MONO_`, ...). Опция `--envs` первым аргументом
  печатает по строке `ИМЯ=значение (default|env|flag)` на каждую переменную.
- **Автодополнение** — через `install-libs/shellcomplete`, если у программы больше трёх
  подкоманд или флагов. Программа передаёт аргументы в `Spec.Handle` до своего разбора; это даёт
  `completion bash|zsh` (скрипт для `source`), `install-completions` / `uninstall-completions`
  (файл в `$XDG_DATA_HOME` и помеченная строка в `~/.bashrc` / `~/.zshrc`) и скрытую
  `__complete`, которую скрипт вызывает на каждый TAB. Образец — `git-repos`.

`check_install.sh` проверяет раздел мягко: устаревшая версия `install-libs`, ручная резолюция
`~/.config` и отсутствие `__complete` дают предупреждения, но не ошибки.

## Рекомендации

### Статическая сборка

Собирать без зависимости от системных библиотек (для Go — `CGO_ENABLED=0` и `-trimpath` плюс
`-ldflags` с версией и источником сборки). Это гарантирует, что исполняемый файл работает на любом
Linux / macOS без внешних зависимостей.

```
-ldflags="-s -w -X main.version=${VERSION} -X main.origin=${ORIGIN} -X main.upstream=${UPSTREAM} -X main.commit=${COMMIT} -X main.channel=${CHANNEL}"
```

### Источник сборки — не основание для доверия

Origin объявлен самой программой: пересборка может заявить любой URL, и ничто внутри исполняемого
файла это заявление не подтверждает. Значение предназначено для диагностики — «из какого зеркала
этот бинарь» — и не должно использоваться для решений о доверии.

В частности, механизм обновления не должен скачивать код или релизы по URL, взятому из исполняемого
файла, без сверки с настроенным пользователем списком разрешённых хостов.

### Зашитый источник ломает побайтовую воспроизводимость

Две сборки одного коммита, сделанные в разных зеркалах, дают разные исполняемые файлы, потому что
зашитый `origin` различается. Поэтому файлы `SHA256SUMS` релизов из разных зеркал нельзя сверять
между собой. Каждое зеркало — самостоятельный канал релизов; сверять контрольные суммы имеет смысл
только внутри одного канала.

### Релиз запускается тегом

Workflow релиза срабатывает на push тега `v*` (GitHub / Gitea — `on.push.tags`, GitLab —
`$CI_COMMIT_TAG`), а не на push в ветку. Версия берётся из имени тега, поэтому workflow не читает
`versions.txt` и не создаёт тегов: тег ставят и пушат рецепты `bump-*`. Обычный push в `master`
релиз не запускает.

### Release-workflow запускается только на своём публичном домене

GitHub-шаблон выполняется только на `github.com`, GitLab-шаблон — только на `gitlab.com`:

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

В зеркалах на других инстансах (приватный GitHub Enterprise, внутренний GitLab, Gitea, читающая
`.github/workflows`) job пропускается. Такие зеркала собирают релизы своими средствами; конвенции
это не регламентируют. `check_install.sh` считает ошибкой GitHub / GitLab release-workflow без
такой защиты.

### Переиспользуемый workflow

Используйте шаблон из этого репозитория — он уже реализует все конвенции: вычисление имени
исполняемого файла (из имени репозитория), сборку для четырёх платформ, генерацию
`SHA256SUMS`, запуск по тегу `vX.Y.Z`.

- GitHub Actions: `workflows/release.yml` → `.github/workflows/release.yml`
- GitLab CI: `workflows/release-gitlab.yml` → `.gitlab-ci.yml`
- Gitea Actions: `workflows/release-gitea.yml` → `.gitea/workflows/release.yml`

Для shell-программ: `release-sh.yml`, `release-sh-gitlab.yml`, `release-sh-gitea.yml`.

Шаблоны взаимозаменяемы: имена архивов, `SHA256SUMS` и формат тега `vX.Y.Z` совпадают, так что
установщики всех платформ работают одинаково. GitLab-шаблон загружает архивы в generic package
registry проекта и прикладывает их к релизу ссылками (release links, а не attachments). Gitea-шаблон не
использует внешних actions (checkout, установка Go и публикация релиза — шаги `run:` на shell,
релиз создаётся через Gitea API), поэтому работает и там, где раннер не может скачивать actions
с github.com.

### Источники установщиков

- `github_install.sh` берёт инстанс из `-s` / `GITHUB_URL` (по умолчанию `https://github.com`), API —
  из `GITHUB_API_URL` (по умолчанию `https://api.github.com`, для других инстансов
  `<GITHUB_URL>/api/v3`), токен — из `GITHUB_TOKEN`;
- `gitlab_install.sh` берёт инстанс из `-s` / `GITLAB_URL` (по умолчанию `https://gitlab.com`),
  токен — из `GITLAB_TOKEN` (scope `read_api`);
- `gitea_install.sh` берёт инстанс из `-s` / `GITEA_URL`, токен — из `GITEA_TOKEN`;
- `go_install.sh` всегда устанавливает из публичного `github.com` через стандартный механизм модулей
  Go и игнорирует `GITHUB_URL` / `GITLAB_URL`: `go install` находит модуль по пути, а не по URL,
  поэтому установка из зеркала потребовала бы перенаправления git и решения вопроса с checksum
  database. Для зеркал используйте release-установщики.

### Создание и проверка

Репозиторий, удовлетворяющий всему описанному выше, создаётся `init_install.sh` из этого
репозитория:

```sh
init_install.sh --lang go --owner <owner> <name>
init_install.sh --lang sh <name>
```

Он пишет `versions.txt`, `justfile` с рецептами `build` / `bump-*` / `release`, `.gitignore`,
workflow релиза (`--ci github,gitlab,gitea`, `all`, `none`) и скелет с `--version` / `--origin` /
`--buildinfo` (для Go — через `install-libs/buildinfo`). Для Go он ещё заполняет `vendor/`,
`.gitattributes`, экспорт `GOWORK` / `GOFLAGS` и рецепты `vendor` / `vendor-check`.

Существующий репозиторий проверяется `check_install.sh` (с `--build` он ещё и собирает бинарь,
смотрит вывод флагов и проверяет согласованность `vendor/`), а `check_install.sh --fix` дописывает
недостающее: `versions.txt`, `.gitignore`, рецепты `bump-*`, workflow релиза и, для Go, `vendor/`,
`.gitattributes`, экспорт `GOWORK` / `GOFLAGS` и рецепты `vendor-*` (для `Makefile` — только
подсказка).
