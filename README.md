# install

Универсальный установщик go-программ из GitHub Releases и шаблон CI-релиза.

## Установка самого установщика в PATH

Чтобы не вводить длинный `curl`-однострочник каждый раз, установите `github_install.sh` в PATH один раз:

```sh
curl -fsSL https://raw.githubusercontent.com/dimkarp93/install/master/local.sh | sh
```

Клонировать репозиторий не нужно. `local.sh` сам скачает актуальный `install.sh` с master и установит его как `github_install.sh` в выбранный каталог (`/usr/bin`, `/usr/local/bin` или `~/.local/bin`).

После этого установка любой программы выглядит так:

```sh
github_install.sh owner/repo
```

## Установка программ через curl (без `github_install.sh`)

Если устанавливать `github_install.sh` не нужно, используйте one-liner напрямую:

```sh
curl -fsSL https://raw.githubusercontent.com/dimkarp93/install/master/install.sh \
  | sh -s -- owner/repo
```

Например, чтобы установить `envs`:

```sh
curl -fsSL https://raw.githubusercontent.com/dimkarp93/install/master/install.sh \
  | sh -s -- dimkarp93/envs
```

Скрипт:
1. Определяет ОС и архитектуру.
2. Скачивает архив последней версии и файл `SHA256SUMS`.
3. Проверяет контрольную сумму архива.
4. Распаковывает и предлагает выбрать каталог установки.
5. Кладёт бинарь в выбранный каталог (при необходимости использует `sudo`).

### Установка конкретной версии

```sh
github_install.sh dimkarp93/envs envs 0.3.0
# или через curl:
curl -fsSL .../install.sh | sh -s -- dimkarp93/envs envs 0.3.0
```

### Интерактивный выбор версии

```sh
github_install.sh -i dimkarp93/envs
```

### Установить в конкретный каталог

Через флаг:

```sh
github_install.sh -d ~/.local/bin dimkarp93/envs
```

Через переменную среды:

```sh
INSTALL_DIR=~/.local/bin github_install.sh dimkarp93/envs
```

### Список доступных версий

```sh
github_install.sh --list dimkarp93/envs
```

### Только скачать архив без установки

Флаг `-D` / `--download` скачивает архив и `SHA256SUMS`, проверяет контрольную сумму и выводит полный путь до архива. Установки не происходит.

```sh
github_install.sh -D dimkarp93/envs
```

По умолчанию файлы сохраняются в текущий каталог. Чтобы указать другой:

```sh
github_install.sh -D -d /tmp/downloads dimkarp93/envs
# или
INSTALL_DIR=/tmp/downloads github_install.sh -D dimkarp93/envs
```

Вывод на успех — только путь до архива (пригоден для скриптов):

```
/tmp/downloads/envs-linux-amd64.tar.gz
```

### Установка из локального архива

Флаг `-F` / `--from-file` устанавливает программу из уже скачанного архива. SHA256SUMS должен лежать рядом с архивом. Флаги версии, `-i` и `-u` игнорируются.

```sh
github_install.sh -F /tmp/downloads/envs-linux-amd64.tar.gz
```

Это прямая замена двухшаговой установке — скачать, затем установить:

```sh
ARCHIVE=$(github_install.sh -D -d /tmp dimkarp93/envs)
github_install.sh -F "$ARCHIVE"
```

Двухшаговый вариант полезен, если нужно проверить архив вручную между загрузкой и установкой, или установить одно и то же на несколько машин без повторного скачивания.

### Приватные репозитории

Для установки из приватного репозитория передайте GitHub-токен с правом `contents: read`:

```sh
GITHUB_TOKEN=ghp_... github_install.sh owner/private-repo
```

Токен используется как при запросах к GitHub API (получение списка релизов), так и при скачивании архива и `SHA256SUMS`. Без токена приватный репозиторий недоступен.

### GitHub API rate-limit

По умолчанию GitHub API разрешает 60 запросов в час без авторизации. При частом использовании передайте токен:

```sh
GITHUB_TOKEN=ghp_... github_install.sh dimkarp93/envs
```

## Обновление

Обновление — это повторная установка. Скрипт покажет текущую версию и спросит подтверждение:

```sh
github_install.sh dimkarp93/envs
```

Чтобы обновить только если доступна более новая версия:

```sh
github_install.sh -u dimkarp93/envs
```

Чтобы обновить без подтверждения:

```sh
INSTALL_FORCE=1 github_install.sh dimkarp93/envs
```

## Требования к программам

Чтобы программа устанавливалась через `github_install.sh`, она должна:

1. **Быть опубликована на GitHub** с тегами вида `vMAJOR.MINOR.PATCH`.
2. **Иметь `versions.txt`** в корне репозитория с голым semver (`0.4.0`).
3. **Прикладывать к релизу архивы** с именами `<имя>-<os>-<arch>.tar.gz` для платформ `linux/amd64`, `linux/arm64`, `darwin/amd64`, `darwin/arm64`.
4. **Прикладывать `SHA256SUMS`** — вывод `sha256sum *.tar.gz`.
5. **Класть исполняемый файл `<имя>`** в корень архива (или в каталог `<имя>-<os>-<arch>/`).
6. **Печатать голый semver** при `--version` (только строка `0.4.0`, без пробелов и лишнего текста).

Полное описание требований — в [CONVENTIONS.md](CONVENTIONS.md).

## Использование шаблона CI-релиза

Скопируйте `workflows/release.yml` в `.github/workflows/release.yml` вашего репозитория. Workflow автоматически:

- читает версию из `versions.txt`,
- собирает статические бинари для 4 платформ,
- генерирует `SHA256SUMS`,
- создаёт GitHub Release с тегом,
- пропускает сборку, если тег уже существует (идемпотентно).

Выпустить новую версию: обновить `versions.txt`, закоммитить, смержить в `main`/`master`.

Если имя бинаря отличается от имени репозитория, задайте переменную репозитория `BIN_NAME` в настройках GitHub Actions.
