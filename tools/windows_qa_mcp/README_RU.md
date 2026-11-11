# GigaCode Desktop → AI Story RPG: локальный Windows QA MCP

**Это самостоятельная интеграция с GigaCode Desktop, НЕ Cline, НЕ VS Code.**

Сервер запускается приложением GigaCode Desktop как **Local MCP (STDIO)**. Он управляет **только** `ai_story_reader.exe` текущего пользователя, читает дерево доступности, сохраняет скриншоты окна и собирает воспроизводимый `report.json`/`report.md`. Не открывает HTTP-порт, не выполняет произвольные команды и не меняет исходные правила RPG Engine. Чистый Dart движок не зависит от MCP.

## 1. Что нужно на Windows

- Windows 10/11 x64, GigaCode **Desktop** с поддержкой локальных MCP-подключений.
- Python **3.12 или новее** (включая 3.15 с совместимыми библиотеками) через `py` или `python` (для установки зависимостей; Windows QA не запускается на Linux-хосте).
- Рабочая копия репозитория ветки PR #133 и **полностью распакованный** Windows portable bundle, включая `data` и `flutter_windows.dll`, а не только EXE.
- Права интерактивного пользователя Windows. В заблокированном сеансе и в Session 0 графическая автоматизация не работает.

```powershell
git clone -b feature/p0-bookwide-gameplay-readiness-20261107 https://github.com/shonentez-afk/AI-Story-RPG.git
cd AI-Story-RPG
.\tools\windows_qa_mcp\setup_gigacode_desktop.ps1 -AppExe 'C:\Games\AI-Story-RPG-Windows\ai_story_reader.exe' -EnableInput
```

Если PowerShell блокирует запуск `.ps1`, можно выполнить эти команды вручную (не меняя политику выполнения системы):

```powershell
py -m venv "$env:LOCALAPPDATA\AIStoryRPG-QA\python"
& "$env:LOCALAPPDATA\AIStoryRPG-QA\python\Scripts\python.exe" -m pip install -r tools\windows_qa_mcp\requirements.txt
```

По умолчанию `setup_gigacode_desktop.ps1` создаёт `%LOCALAPPDATA%\AIStoryRPG-QA\gigacode-desktop-mcp.json` **и не меняет конфигурацию самого GigaCode Desktop**. Ключ `-EnableInput` включает управление мышью/клавиатурой: без него доступны только чтение и подключение, а запуск, клики и ввод заблокированы. Никогда не включайте ввод на рабочем ПК без осознания действий агента.

## Исправление MCP STDIO для GigaCode Desktop (11.11.2026)

**Ранее GigaCode не видел инструменты:** старый запуск `-m tools.windows_qa_mcp.server` зависел от рабочего каталога `cwd`, а `--self-check` проверял только импорт библиотеки. Настройки GigaCode Desktop могут не передать `cwd` серверу.

Новый установщик создаёт конфигурацию с **абсолютным путём к загрузчику** `launch_gigacode.py`. Загрузчик импортирует проект независимо от текущей рабочей папки, запускает MCP без лишних строк в STDOUT и сохраняет ошибки запуска в `%LOCALAPPDATA%\AIStoryRPG-QA\mcp-startup-errors.log`.

После `git pull --ff-only` обязательно **повторно запустите установщик** с правильным путём к EXE, чтобы получить новые `args`:

```powershell
.\tools\windows_qa_mcp\setup_gigacode_desktop.ps1 -AppExe 'C:\Games\AI-Story-RPG-Windows\ai_story_reader.exe' -EnableInput
```

Установщик теперь выполняет две проверки до создания JSON:

1. `launch_gigacode.py --self-check`: построить FastMCP и зарегистрировать **ровно 17 инструментов**;
2. `protocol_smoke.py`: настоящий MCP STDIO `initialize` → `tools/list` → `qa_status` → `qa_begin` → `qa_report` с запуском Python **из другой рабочей папки** и без `PYTHONPATH`.

Если в GigaCode уже есть старый сервер, **вручную замените его команду и аргументы** новыми значениями из JSON. Наличие JSON на диске не меняет настройки GigaCode автоматически. В интерфейсе GigaCode `Команда` — только полный путь к `python.exe`; `Аргументы` — **`-u` и абсолютный путь к `launch_gigacode.py`** (не `-m tools...`). `cwd` и три `AI_STORY_QA_*` переменные из JSON сохранить. При необходимости отключите старую запись и добавьте новую; настройки x64dbg не менять.

**Диагностика без GigaCode:**

```powershell
$cfg = (Get-Content "$env:LOCALAPPDATA\AIStoryRPG-QA\gigacode-desktop-mcp.json" -Raw | ConvertFrom-Json).mcpServers.'ai-story-rpg-windows-qa'
& $cfg.command $cfg.args[0] $cfg.args[1] --self-check
& $cfg.command -u (Join-Path $cfg.cwd 'tools\windows_qa_mcp\protocol_smoke.py')
```

Если эта проверка проходит, но GigaCode не видит инструменты, причина вероятнее в настройках/состоянии подключения GigaCode Desktop. Снимите фактический статус сервера в MCP-панели, а не объявляйте PASS по процессам Python. Если проверка падает, сохраните текст ошибки и `mcp-startup-errors.log`. Без настоящего `qa_status` из GigaCode приёмка Windows GUI не выполнена.

## 2. Подключение в GigaCode Desktop (не в Cline)

Откройте в **GigaCode Desktop** `Settings` → `MCP` → `Add server` → `Local / STDIO` (названия могут различаться по версии). В созданном установщиком файле возьмите команду запуска, аргументы, рабочую папку `cwd` и переменные `env`. Формат соответствует официальному `mcpServers`:

```json
{
  "mcpServers": {
    "ai-story-rpg-windows-qa": {
      "command": "C:\\Users\\YOU\\AppData\\Local\\AIStoryRPG-QA\\python\\Scripts\\python.exe",
      "args": ["-u", "C:\\path\\AI-Story-RPG\\tools\\windows_qa_mcp\\launch_gigacode.py"],
      "cwd": "C:\\path\\AI-Story-RPG",
      "env": {
        "AI_STORY_QA_EXE": "C:\\Games\\AI-Story-RPG-Windows\\ai_story_reader.exe",
        "AI_STORY_QA_OUTPUT": "C:\\Users\\YOU\\AppData\\Local\\AIStoryRPG-QA\\evidence",
        "AI_STORY_QA_ALLOW_INPUT": "1"
      }
    }
  }
}
```

**Важно:** это JSON-**фрагмент**, а не файл, который нужно целиком перезаписать поверх существующих MCP-настроек. В GUI `command` = полный путь к Python из виртуального окружения, `args` = `-u`, абсолютный путь к `launch_gigacode.py`, рабочий каталог = корень `AI-Story-RPG`. Если Desktop предоставляет вставку JSON, **добавьте** этот сервер в существующую конфигурацию. У GigaCode CLI другой путь настроек; не подменяйте Desktop-способ рекомендациями для CLI или расширения IDE.

Проверка из терминала (без запуска MCP):

```powershell
& "$env:LOCALAPPDATA\AIStoryRPG-QA\python\Scripts\python.exe" -u "$PWD\tools\windows_qa_mcp\launch_gigacode.py" --self-check
```

Проверка из **GigaCode Desktop**: в режиме агента попросите: «Перечисли инструменты `ai-story-rpg-windows-qa`, вызови `qa_status`, затем `qa_begin` с именем `desktop-smoke`, запусти `qa_attach` или `qa_launch`, `qa_tree`, `qa_screenshot`, `qa_report`».

## 3. Доступные инструменты

| MCP tool | Что делает |
| --- | --- |
| `qa_status` | Проверяет конфигурацию и доступные PID, без управления |
| `qa_begin` | Создаёт каталог независимого QA-прогона |
| `qa_attach` / `qa_launch` | Привязка к точному пути доверенного EXE / запуск исключительно настроенного EXE |
| `qa_close` | Попросить приложение завершиться штатно; не убивает процессы, позволяет проверить повторный запуск |
| `qa_tree` | Читает дерево Windows UI Automation (`name`, `automation_id`, `node_id`, состояния) |
| `qa_screenshot` | Снимок **только** окна игры; возвращает PNG как MCP image, сохраняет доказательство |
| `qa_click` | Щелчок по однозначному UIA-узлу; при дубликатах требует `node_id` |
| `qa_click_xy` | Ограниченный клик по координатам **последнего скриншота игры**, а не рабочего стола |
| `qa_set_text` / `qa_type_focused` | Ввод текста в поле игры с UIA / уже сфокусированное поле |
| `qa_press` / `qa_scroll` | Только разрешённые навигационные клавиши и прокрутка |
| `qa_wait_text` / `qa_assert` | Ожидание/проверка доступного текста, запись PASS/FAIL |
| `qa_note` | Явно фиксирует BLOCKED/INCONCLUSIVE/SKIPPED сценарии, которые не удалось испытать; не разрешает ставить PASS без проверок |
| `qa_report` | Финальный `report.json`, `report.md` и ссылки на PNG; BLOCKED не превращается в PASS |

Без обязательного `AI_STORY_QA_EXE` сервер **не подключается ни к одному процессу**. Снимок ограничен прямоугольником окна игры, но если поверх него находится другое окно/уведомление, оно теоретически может попасть на снимок: не запускайте QA на рабочем столе с конфиденциальными данными.

`qa_assert(present=false)` **не выдаёт ложный PASS**, если дерево UIA пустое или усечённое: будет `inconclusive=true`. У Flutter Windows в конкретной Release-сборке доступность некоторых виджетов может отличаться: тогда снимок + ограниченный `qa_click_xy` применимы, но одно изображение не доказывает внутреннее состояние RPG. Для причинности/NPC требуется отдельная сверка с логом решений и автономными Dart/API-тестами.

## 4. Практический агентский сценарий для GigaCode Desktop

Скопируйте текст из [GIGACODE_QA_PROMPT_RU.md](./GIGACODE_QA_PROMPT_RU.md) в **GigaCode Desktop**, открыв именно этот проект. Агент должен прогнать старт, библиотеку, FB2, единый маршрут RPG, Герой/Предметы/Журнал, NPC, CANON/ALTER_FATE, сохранение и повторный запуск. Источник `.bworld` для книжной причинности нужно подготовить и проверить **заранее**; без него нельзя утверждать полноту адаптации книги.

**Запрещено** записывать в отчёты API-ключи и личные книги, самовольно подтверждать платные или внешние ИИ-запросы, удалять реальные сохранения, запускать другие EXE, менять глобальные настройки Windows. Перед любым внешним ИИ-действием требуется отдельное согласие пользователя в самом приложении.

## 5. Статус приёмки

`python -m unittest discover -s tools/windows_qa_mcp/tests -v` запускает независимые тесты безопасного контура на Linux и Windows. Их успешность **не означает**, что UIA обнаруживает все Flutter-виджеты в собранном EXE или что агент GigaCode Desktop уже реально подключён. Доказательство интеграции — реальный тест в Windows и полученные `report.json` + скриншоты. До него PR #133 нельзя считать прошедшим полноценную ручную/агентскую приёмку.