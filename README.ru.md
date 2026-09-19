# install

*Языки: **Русский** · [English](README.en.md)*

Универсальный установщик программ из GitHub и Gitea Releases и шаблон CI-релиза.

Программа может быть написана на любом языке — установщикам важны лишь готовый исполняемый
файл и соблюдение [конвенций](CONVENTIONS.ru.md). Отдельно есть `go_install.sh` — необязательный
установщик для Go-программ поверх штатного `go install`, для тех, у кого уже стоит Go.

## Установка установщиков в PATH

Чтобы не вводить длинную команду `curl` каждый раз, установите установщики
(`github_install.sh`, `gitea_install.sh`, `local_install.sh`, `go_install.sh`,
`check_install.sh` и `init_install.sh`) в PATH один раз:

```sh
curl -fsSL https://raw.githubusercontent.com/dimkarp93/install/master/bootstrap.sh | sh
```

Клонировать репозиторий не нужно. `bootstrap.sh` сам скачает актуальные установщики с master и
поместит их в `/usr/local/bin` (при необходимости — через `sudo`). Чтобы установить без `sudo`
в `~/.local/bin`, добавьте `--user-only`:

```sh
curl -fsSL https://raw.githubusercontent.com/dimkarp93/install/master/bootstrap.sh | sh -s -- --user-only
```

После этого установка любой программы выглядит так:

```sh
github_install.sh owner/repo
```

### Установка из рабочей копии (`dev-bootstrap.sh`)

Если вы правите сами установщики, `dev-bootstrap.sh` устанавливает их не из GitHub, а из текущей
рабочей копии этого репозитория. Запускать из каталога с исходниками:

```sh
./dev-bootstrap.sh             # в /usr/local/bin
./dev-bootstrap.sh --user-only # в ~/.local/bin
```

## Установка программ через curl (без `github_install.sh`)

Если устанавливать `github_install.sh` не нужно, используйте команду `curl` напрямую:

```sh
curl -fsSL https://raw.githubusercontent.com/dimkarp93/install/master/github_install.sh \
  | sh -s -- owner/repo
```

Скрипт:
1. Определяет ОС и архитектуру.
2. Скачивает архив последней версии и файл `SHA256SUMS`.
3. Проверяет контрольную сумму архива.
4. Распаковывает и устанавливает исполняемый файл в `/usr/local/bin` (или в `~/.local/bin`
   с `--user-only`; при необходимости использует `sudo`).

### Каталог установки

По умолчанию исполняемый файл устанавливается в `/usr/local/bin`. С флагом `--user-only` —
в `~/.local/bin` (без `sudo`):

```sh
github_install.sh --user-only owner/repo
```

### Установка конкретной версии

```sh
github_install.sh owner/repo myapp 0.3.0
# или через curl:
curl -fsSL .../github_install.sh | sh -s -- owner/repo myapp 0.3.0
```

### Интерактивный выбор версии

```sh
github_install.sh -i owner/repo
```

### Список доступных версий

```sh
github_install.sh --list owner/repo
```

### Только скачать архив без установки

Флаг `-D` / `--download` скачивает архив и `SHA256SUMS`, проверяет контрольную сумму и
выводит полный путь до архива. Установка не выполняется.

```sh
github_install.sh -D owner/repo
```

Файлы сохраняются в текущий каталог. При успехе в стандартный вывод печатается только путь
до архива (пригодно для использования в скриптах):

```
/tmp/downloads/myapp-linux-amd64.tar.gz
```

### Установка из локального архива

Флаг `-F` / `--from-file` устанавливает программу из уже скачанного архива. Файл
`SHA256SUMS` должен находиться рядом с архивом. Флаги версии, `-i` и `-u` игнорируются.

```sh
github_install.sh -F /tmp/downloads/myapp-linux-amd64.tar.gz
```

Это прямая замена двухшаговой установке — скачать, затем установить:

```sh
ARCHIVE=$(github_install.sh -D owner/repo)
github_install.sh -F "$ARCHIVE"
```

Двухшаговый вариант полезен, если нужно проверить архив вручную между загрузкой и
установкой или установить одно и то же на несколько машин без повторного скачивания.

### Приватные репозитории

Для установки из приватного репозитория передайте GitHub-токен с правом `contents: read`:

```sh
GITHUB_TOKEN=ghp_... github_install.sh owner/private-repo
```

Токен используется как при запросах к GitHub API (получение списка релизов), так и при
скачивании архива и `SHA256SUMS`. Без токена приватный репозиторий недоступен.

### Лимит запросов GitHub API

По умолчанию GitHub API разрешает 60 запросов в час без авторизации. При частом
использовании передайте токен:

```sh
GITHUB_TOKEN=ghp_... github_install.sh owner/repo
```

## Установка из Gitea (`gitea_install.sh`)

`gitea_install.sh` устанавливает программу из релизов self-hosted Gitea — например из тех, что
собирает шаблон `workflows/release-gitea.yml`. Скрипт делает ровно то же, что и
`github_install.sh` (определяет ОС и архитектуру, скачивает архив и `SHA256SUMS`, проверяет
контрольную сумму, распаковывает и устанавливает исполняемый файл), и понимает те же флаги.
Требования к релизу — те же, что и для GitHub: архивы `<имя>-<os>-<arch>.tar.gz`, файл
`SHA256SUMS`, теги `vX.Y.Z` (см. [CONVENTIONS.ru.md](CONVENTIONS.ru.md)).

Отличие одно: обязателен адрес инстанса Gitea — флаг `-s` / `--server`.

```sh
gitea_install.sh -s https://git.example.com owner/repo
```

Схему можно не писать — подставится `https://`:

```sh
gitea_install.sh -s git.example.com owner/repo
```

Вместо флага адрес можно задать переменной среды `GITEA_URL`:

```sh
export GITEA_URL=https://git.example.com
gitea_install.sh owner/repo
```

Через `curl` без установки скрипта:

```sh
curl -fsSL https://raw.githubusercontent.com/dimkarp93/install/master/gitea_install.sh \
  | sh -s -- -s https://git.example.com owner/repo
```

### Остальные флаги

Работают так же, как у `github_install.sh` (см. разделы выше): `-i` — интерактивный выбор версии,
`--list` — список версий, `-u` — обновить только при наличии новой версии, `-D` — только скачать
архив с проверкой суммы, `-F` — установить из локального архива, `--user-only` — установка в
`~/.local/bin`. Позиционные аргументы те же: `<владелец/репозиторий> [имя-бинаря] [версия]`.

```sh
gitea_install.sh -s https://git.example.com --list owner/repo
gitea_install.sh -s https://git.example.com -i --user-only owner/repo
gitea_install.sh -s https://git.example.com owner/repo myapp 0.3.0
```

Флагу `-F` адрес сервера не нужен — сеть не используется:

```sh
ARCHIVE=$(gitea_install.sh -s https://git.example.com -D owner/repo)
gitea_install.sh -F "$ARCHIVE"
```

### Приватные репозитории

Установка из приватного репозитория работает — нужен токен Gitea. Получить его:
_Settings → Applications → Generate New Token_, права — `read:repository` (этого достаточно, `write`
не нужен). Токен передаётся в переменной `GITEA_TOKEN`:

```sh
GITEA_TOKEN=... gitea_install.sh -s https://git.example.com owner/private-repo
```

Токен подставляется во все запросы: и в Gitea API (`/api/v1/repos/...` — список релизов, поиск
ассетов), и в скачивание архива и `SHA256SUMS`. Работает со всеми флагами, включая `-D`, `-i` и
`--list`:

```sh
export GITEA_URL=https://git.example.com
export GITEA_TOKEN=...
gitea_install.sh --list owner/private-repo
gitea_install.sh -u owner/private-repo
```

Ссылки на архив и `SHA256SUMS` не собираются вручную, а берутся из ответа API
(`browser_download_url` ассета) — поэтому установка не ломается, если инстанс раздаёт вложения с
нестандартного пути или из внешнего хранилища.

Без токена приватный репозиторий недоступен: Gitea ответит `401`/`404`, и скрипт подскажет задать
`GITEA_TOKEN`. Публичным репозиториям токен не нужен.

## Установка Go-программ через `go install` (`go_install.sh`)

`go_install.sh` — необязательная альтернатива для тех, у кого уже установлен Go.
Он не скачивает релизные архивы, а собирает программу штатным `go install` прямо из
исходников модуля и кладёт исполняемый файл в PATH.

```sh
go_install.sh github.com/dimkarp93/md-pdf
go_install.sh --user-only github.com/dimkarp93/md-pdf
go_install.sh github.com/dimkarp93/md-pdf 0.3.0
go_install.sh --list github.com/dimkarp93/md-pdf
```

Релиз, архивы и `SHA256SUMS` при этом не нужны — версия берётся из git-тега
репозитория, а целостность публичных модулей проверяет `sum.golang.org`.

### Когда использовать, а когда нет

Используйте `go_install.sh`, если Go уже стоит, программа написана на Go и её модуль
соответствует [Go-конвенциям](CONVENTIONS.ru.md#go-программы-требования-для-go-install-необязательно).

Используйте `github_install.sh` / `gitea_install.sh`, если:

- на машине нет Go (установщики релизов ставят готовый бинарь и Go не требуют);
- программа написана не на Go;
- машина в закрытом контуре: зависимости модуля тянутся с `proxy.golang.org` или
  напрямую с github.com, тогда как установщику релизов достаточно доступа к самому
  Gitea.

Флаги `-D`, `-F`, `-i`, `-u` не поддерживаются: у `go install` нет промежуточного
архива, на котором эти сценарии построены. Для них используйте `github_install.sh` или
`gitea_install.sh`.

### Определение пакета и имени бинаря

Имя исполняемого файла `go install` берёт из последнего сегмента пути пакета. Скрипт
сначала пробует `<модуль>/cmd/<имя>` (рекомендуемая структура), затем корень модуля.
Суффикс major-версии (`/v2`, `/v3`) при вычислении имени отбрасывается. Путь пакета
можно задать явно:

```sh
go_install.sh -p golang.org/x/tools/cmd/stringer golang.org/x/tools
```

### Каталог установки

По умолчанию — `/usr/local/bin` (при необходимости через `sudo`), с `--user-only` —
`~/.local/bin`. Флаг `--gobin` оставляет бинарь там, куда его кладёт сам `go install`
(`$GOBIN`, по умолчанию `~/go/bin`).

### Приватные репозитории

Прокси `proxy.golang.org` приватные модули не отдаёт, поэтому нужно указать `go`
ходить в git напрямую и настроить доступ:

```sh
export GOPRIVATE='github.com/dimkarp93/*'
go_install.sh github.com/dimkarp93/md-pdf
```

Доступ git настраивается обычным способом — SSH-ключ или `~/.netrc`. Токены
`GITHUB_TOKEN` / `GITEA_TOKEN` здесь не используются: их понимают только
`github_install.sh` и `gitea_install.sh`.

Для модуля в Gitea путь модуля должен начинаться с адреса инстанса
(`module git.example.com/owner/repo`), а `GOPRIVATE` — включать этот хост. Если Gitea
доступна только по SSH на нестандартном порту, добавьте подмену:

```sh
git config --global url."ssh://git@git.example.com:2222/".insteadOf "https://git.example.com/"
export GOPRIVATE='git.example.com/*'
go_install.sh git.example.com/owner/repo
```

## Локальная установка из исходников (`local_install.sh`)

`local_install.sh` устанавливает программу прямо из рабочей копии git-репозитория — без
публикации GitHub Release. Удобно на этапе разработки: правка кода, локальная установка,
проверка — без выпуска релиза.

Имя исполняемого файла берётся из имени каталога репозитория. Анализировать файл workflow
больше не нужно.

### Конфигурация корней

Скрипт ищет программы по списку каталогов-корней из `~/.config/install/roots.txt`:
по одному каталогу на строку, `#`-комментарии и пустые строки игнорируются, `~`
раскрывается в домашний каталог текущего пользователя. Если файла нет или он пуст —
единственный корень по умолчанию `~/tools`.

```
# ~/.config/install/roots.txt
~/tools
~/dev
```

### Примеры использования

Установить программу из текущего каталога (путь не указан):

```sh
cd ~/dev/myapp
local_install.sh
```

По имени (ищется в корнях):

```sh
local_install.sh myapp
```

По абсолютному пути:

```sh
local_install.sh ~/dev/myapp
```

В `~/.local/bin` без `sudo`:

```sh
local_install.sh --user-only myapp
```

### Требования к репозиторию

Помимо стандартных требований из [CONVENTIONS.ru.md](CONVENTIONS.ru.md), для локальной установки
нужно:

- **Наличие цели сборки**: `just build` (Justfile) или `make build` (Makefile).
- **Исполняемый файл в корне**: цель сборки должна помещать исполняемый файл `<имя>` прямо
  в корень репозитория.
- **Имя исполняемого файла**: совпадает с именем каталога.

## Создание новой программы (`init_install.sh`)

`init_install.sh` создаёт репозиторий, который сразу соответствует
[CONVENTIONS.ru.md](CONVENTIONS.ru.md), — одна команда вместо ручного копирования шаблонов:

```sh
init_install.sh --lang go --owner dimkarp93 mytool   # ./mytool в текущем каталоге
init_install.sh --lang sh ~/dev/mytool               # по абсолютному пути
```

Что оказывается в репозитории:

| Файл | Назначение |
|---|---|
| `versions.txt` | `0.1.0` — источник истины для версии |
| `justfile` | `build`, `check`, `bump-patch/minor/major`, `release`, `install`, `clean` |
| `.gitignore` | собранный в корне исполняемый файл, `dist/` |
| `cmd/<name>/main.go` или `<name>.sh` | скелет с `--version` / `--origin` / `--buildinfo` |
| `go.mod` | `module <host>/<owner>/<name>` (для `--lang go`) |
| `.github/workflows/release.yml` | workflow релиза (`--ci gitea` или `--ci both` добавят Gitea-вариант) |
| `README.md` | как установить, собрать и выпустить |

Для `--lang go` скелет использует
[`install-libs/buildinfo`](https://github.com/dimkarp93/install-libs), то есть три флага
реализует библиотека, а не ручной код; зависимость `init_install.sh` подтягивает сам.
Для `--lang sh` значения `VERSION` / `ORIGIN` / `UPSTREAM` / `COMMIT` / `CHANNEL` подставляются в
скрипт рецептом `build` и workflow.

Флаги:

```
--lang go|sh                  язык скелета (по умолчанию go)
--owner OWNER                 владелец репозитория (обязателен для --lang go)
--host HOST                   хост репозитория (по умолчанию github.com)
--upstream URL                записать upstream.txt (для зеркал)
--layout cmd|root             go: cmd/<name>/main.go (по умолчанию) или main.go в корне
--ci github|gitea|both|none   какой workflow релиза положить (по умолчанию github)
--remote URL                  git remote add origin URL
--no-git                      не делать git init и первый коммит
--force                       достроить существующий каталог (существующие файлы сохраняются)
--emit TEMPLATE               напечатать шаблон в stdout и выйти

<name|path>                   абсолютный путь либо имя или относительный путь -
                              разрешается относительно текущего каталога
```

Ни один существующий файл не перезаписывается: уже имеющийся файл отмечается как `[skip]`. Поэтому
команду безопасно запускать с `--force` поверх наполовину готового репозитория. В конце
`init_install.sh` прогоняет по результату `check_install.sh`, так что из вывода сразу видно,
соответствует ли репозиторий конвенциям.

Выпуск программы дальше — тоже одна команда:

```sh
just release patch    # bump versions.txt -> коммит -> push; тег и релиз делает workflow
```

`--emit` печатает шаблон, ничего не создавая, — это единственный источник шаблонов: из него
генерируются файлы в `workflows/` (`just sync-workflows`), оттуда же берёт заготовки
`check_install.sh --fix`.

## Проверка соответствия конвенциям (`check_install.sh`)

`check_install.sh` проверяет, что репозиторий соответствует [CONVENTIONS.ru.md](CONVENTIONS.ru.md):
наличие `.git`, корректный `versions.txt`, имя исполняемого файла (из имени каталога),
цель сборки, цели `bump-*`, workflow релиза (включая `SHA256SUMS` и архивы по платформам), формат
git-тегов, `versions.txt` относительно последнего тега, исполняемый файл в `.gitignore` и источник
сборки (корректный `upstream.txt`, если он есть, и подстановку origin в цели сборки и в workflow
релиза). Если есть `go.mod`, дополнительно проверяются требования раздела про `go install`:
сетевой путь модуля, его последний сегмент против имени бинаря, суффикс `/vN` для мажорных версий
от `2.0.0`, отсутствие `replace` и расположение `package main`. Аргумент — путь к репозиторию:
абсолютный путь либо имя или относительный путь, который разрешается относительно текущего
каталога. Если путь не указан, берётся текущий каталог.

```sh
check_install.sh                 # текущий каталог
check_install.sh myapp           # ./myapp в текущем каталоге
check_install.sh ~/dev/myapp     # по абсолютному пути
```

Флаг `--build` дополнительно собирает исполняемый файл и проверяет его вывод: что `--version`
выводит версию из `versions.txt`, а `--origin` — один канонический URL (или `local`) без учётных
данных внутри:

```sh
check_install.sh --build myapp
```

Без `--build` проверки источника сборки дают `[WARN]`: миграция существующих инструментов ещё не
закончена, поэтому отсутствие подстановки origin не роняет проверку. С `--build` сломанный или
отсутствующий `--origin` — это `[FAIL]`.

Каждая проверка помечается `[OK]` / `[WARN]` / `[FAIL]`. Код выхода `0` — все обязательные
требования выполнены, `1` — есть ошибки (предупреждения на код выхода не влияют).

### Починка недостающего (`--fix`)

Флаг `--fix` создаёт недостающее перед проверкой — и только недостающее: ничего из того, что уже
есть в репозитории, не перезаписывается, поэтому флаг идемпотентен:

```sh
check_install.sh --fix myapp
```

- нет `versions.txt` → создаётся с `0.1.0`;
- нет `.gitignore` или в нём нет исполняемого файла → создаётся или дополняется строками `/<name>`
  и `/dist/`;
- нет рецептов `bump-*` в `justfile` → дописываются в конец;
- нет ни одного workflow релиза → добавляется `.github/workflows/release.yml` (Go- или
  shell-вариант, в зависимости от наличия `go.mod`).

`Makefile` автоматически не правится: синтаксис целей отличается, поэтому `--fix` только сообщает,
что цели `bump-*` нужно добавить руками (готовый блок есть в
[CONVENTIONS.ru.md](CONVENTIONS.ru.md)).

Шаблоны берутся из `init_install.sh --emit`, поэтому для `--fix` нужен `init_install.sh` в PATH
или рядом с `check_install.sh`; оба ставит `bootstrap.sh`.

## Обновление

Обновление — это повторная установка: исполняемый файл в PATH перезаписывается. Скрипт сам
определит последнюю версию и установит её:

```sh
github_install.sh owner/repo
```

Чтобы обновить только при наличии более новой версии:

```sh
github_install.sh -u owner/repo
```

### Из какого зеркала этот бинарь

Одну и ту же программу можно установить из upstream на GitHub или из зеркала в Gitea. Установленный
исполняемый файл сам сообщает, из какого репозитория он собран:

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

Значение объявлено самой программой и предназначено для диагностики — оно не доказывает, откуда
исполняемый файл взялся на самом деле, и не должно служить основанием для доверия. См. раздел
«Источник сборки» в [CONVENTIONS.ru.md](CONVENTIONS.ru.md).

## Требования к программам

Чтобы программу можно было устанавливать установщиками этого репозитория, она должна:

1. **Быть опубликована на GitHub** с тегами вида `vMAJOR.MINOR.PATCH`.
2. **Иметь `versions.txt`** в корне репозитория с версией в формате semver (`0.4.0`).
3. **Иметь имя исполняемого файла**, равное имени репозитория.
4. **Прикладывать к релизу архивы** с именами `<имя>-<os>-<arch>.tar.gz` для платформ
   `linux/amd64`, `linux/arm64`, `darwin/amd64`, `darwin/arm64`.
5. **Прикладывать `SHA256SUMS`** — вывод `sha256sum *.tar.gz`.
6. **Помещать исполняемый файл `<имя>`** в корень архива (или в каталог
   `<имя>-<os>-<arch>/`).
7. **Выводить версию в формате semver** при `--version` (только строка `0.4.0`, без
   пробелов и лишнего текста).
8. **Выводить репозиторий-источник** при `--origin` — одна строка с каноническим URL репозитория,
   из которого собран исполняемый файл, — и остальные атрибуты сборки при `--buildinfo`, строками
   `key=value`.

Полное описание требований — в [CONVENTIONS.ru.md](CONVENTIONS.ru.md).

## Использование шаблона CI-релиза

В каталоге `workflows/` лежат четыре равнозначных шаблона — выберите по платформе и языку
программы (`init_install.sh` кладёт нужный сам):

| Платформа | Go | POSIX shell | Куда копировать |
|---|---|---|---|
| GitHub Actions | `workflows/release.yml` | `workflows/release-sh.yml` | `.github/workflows/release.yml` |
| Gitea Actions | `workflows/release-gitea.yml` | `workflows/release-sh-gitea.yml` | `.gitea/workflows/release.yml` |

Shell-шаблоны собирают исполняемый файл подстановкой версии и origin в `<name>.sh` (или
`<name>-init.sh`) через `sed` вместо `go build` и проверяют исходник через `sh -n`; всё
остальное — имена архивов, `SHA256SUMS`, тег, идемпотентность — идентично.

Файлы в `workflows/` генерируются из шаблонов, встроенных в `init_install.sh`:
`just sync-workflows` обновляет их, `just check` падает, если они разъехались.

Все workflow делают одно и то же:

- читают версию из `versions.txt`,
- определяют имя исполняемого файла из имени репозитория,
- собирают статические исполняемые файлы для четырёх платформ,
- генерируют `SHA256SUMS`,
- создают релиз с тегом `vX.Y.Z`,
- пропускают сборку, если тег уже существует (идемпотентно).

Имена архивов, `SHA256SUMS` и формат тега одинаковы на обеих платформах. Релиз из GitHub ставится
`github_install.sh`, релиз из Gitea — `gitea_install.sh` (с флагом `-s`, см. раздел
[Установка из Gitea](#установка-из-gitea-gitea_installsh)); отличаются они только адресами API и
загрузки, набор флагов один и тот же.

Выпуск новой версии: повысить версию (`just bump-patch` / `bump-minor` / `bump-major` —
см. [CONVENTIONS.ru.md](CONVENTIONS.ru.md)), зафиксировать `versions.txt` и влить в ветку
`main` / `master`.

### Особенности Gitea-шаблона

`workflows/release-gitea.yml` не использует ни одного внешнего action: `actions/checkout` и
`actions/setup-go` заменены на шаги `run:` (shell), а `gh release create` — на вызовы Gitea
API через `curl`. Это нужно потому, что Gitea тянет actions с github.com, и в закрытом
контуре они недоступны. Что это значит на практике:

- **Checkout** — `git init` + shallow-fetch коммита `$GITHUB_SHA` из `$GITHUB_SERVER_URL`.
- **Go** — версия читается из `go.mod` (директива `toolchain`, иначе `go`); если указана
  только `X.Y`, точный патч резолвится через `https://go.dev/dl/?mode=json`. Тарбол ставится
  в `$HOME/.local/go` (root не нужен). Раннеру требуется доступ к `go.dev`.
- **Релиз** — `POST /api/v1/repos/{owner}/{repo}/releases`: Gitea сама создаёт тег из
  `target_commitish`, отдельный `git push --tags` не нужен. Затем архивы и `SHA256SUMS`
  загружаются как assets.
- **Токен** — `secrets.GITHUB_TOKEN`, который Gitea выдаёт каждому job автоматически;
  заводить секрет вручную не нужно. Если API отвечает `403`, включите запись для токена
  Actions в настройках репозитория или подставьте свой токен с правом `write:repository`.
- **`runs-on: ubuntu-latest`** — это метка (label) раннера. Если ваш `act_runner`
  зарегистрирован с другими метками, поправьте `runs-on` под них.
