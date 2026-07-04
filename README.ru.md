# Developer Cleanup Utility

[English version](README.md)

`dev-cleanup.sh` - интерактивная утилита для очистки рабочей машины разработчика. Она помогает смотреть, что занимает место, и чистить типичные локальные кэши Xcode/iOS, Docker и Claude без привязки к одной фиксированной папке с проектами.

## Возможности

- Структурированное терминальное меню с разделами overview, Xcode/iOS, developer tools и batch cleanup.
- Настраиваемый корень сканирования для поиска проектов и локальных кэшей.
- Поиск Xcode-проектов и workspace: `.xcodeproj` и `.xcworkspace`.
- Отчеты по размеру Xcode DerivedData, iOS DeviceSupport, Archives, Claude VM Bundles и локальных `.derivedData`.
- Top 20 больших папок для расследования, что занимает место в проекте.
- Спиннеры, progress bars, подтверждения и статусные сообщения для долгих операций.
- Очистка Docker через `docker system prune -a --volumes`.

## Установка

Сделать скрипт исполняемым:

```bash
chmod +x dev-cleanup.sh
```

Опционально установить в домашнюю директорию:

```bash
install -m 755 dev-cleanup.sh ~/dev-cleanup.sh
```

## Запуск

Из домашней директории:

```bash
~/dev-cleanup.sh
```

Или из репозитория:

```bash
./dev-cleanup.sh
```

По умолчанию утилита использует `~/Code` как корень сканирования, если такая папка есть. Если ее нет, используется `~`.

Корень сканирования можно переопределить:

```bash
DEFAULT_SCAN_ROOT=~/Projects ./dev-cleanup.sh
```

## Меню

```text
Overview
  1  Показать размеры
  2  Top 20 больших папок

Xcode / iOS
  3  Найти проекты и workspace
  4  Очистить локальные .derivedData
  5  Очистить глобальный DerivedData
  6  Очистить iOS DeviceSupport
  7  Очистить Archives
  8  Удалить unavailable Simulators

Developer Tools
  9  Docker system prune
 10  Claude VM Bundles cleanup

Batch
 11  Полная очистка Xcode/iOS
  0  Выход
```

## Безопасность

Перед действиями, которые удаляют файлы, утилита спрашивает подтверждение. Поиск проектов и отчеты по размеру ничего не удаляют.

`Полная очистка Xcode/iOS` все равно проходит через отдельные подтверждения на каждом шаге.

## Требования

- macOS
- Bash
- Xcode command line tools для очистки unavailable simulators
- Docker для Docker cleanup

Утилита не собирает проекты и не запускает `xcodebuild`.
