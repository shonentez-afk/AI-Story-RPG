# Исследование готовых движков текстовых RPG и интерактивных историй на GitHub

**Дата аудита:** 2026-11-01. **Статус:** изучены исходники, манифесты, лицензии, документация и структура тестов через GitHub; **исходники в наш проект пока не переносились, их тесты здесь не выполнялись**.

**Контекст:** нормативное [ТЗ](TZ_RU.md) требует Flutter/Dart (Android + Windows), offline-first, классический выбор действий без ИИ, сюжетные флаги, инвентарь/NPC, сохранения, `.bworld`, сменяемое LLM-подключение. Задача — уменьшить объём разработки, не меняя принятую архитектуру и не приклеивая игру к веб-серверу/чужому формату.

## Короткое решение

**В M0 выполнить сравнительный прототип двух кандидатов на общий runtime:** 
1. [ErikSchultheiss/story_engine](https://github.com/ErikSchultheiss/story_engine) — **кандидат №1 для структурированного `.bworld` и детерминированного классического режима**;
2. [dennerkrans/ink_dart](https://github.com/dennerkrans/ink_dart) + Flutter-пакет `flutter_ink` — **кандидат №2 для максимально быстрого запуска готовых ветвящихся текстовых историй и диалогов**.

По результатам испытаний выбрать **один** основной runtime. Не допускать неконтролируемой работы сразу двух независимых систем правил/сохранений в одном прохождении. Для второго варианта в будущем может существовать отдельный импортный адаптер.

## 1. Сравнительная таблица

| Проект | Лицензия проверена | Язык/платформы | Уже есть | Чего нет для AI Story RPG | Вердикт |
|---|---|---|---|---|---|
| [story_engine](https://github.com/ErikSchultheiss/story_engine) | **BSD-3-Clause** (LICENSE) | Чистый Dart; подходит Flutter Windows/Android | Условные/взвешенные переходы, типизированные скалярные переменные, эффекты, валидация, воспроизводимый RNG, snapshot + восстановление, версионированный переносимый Story Format v1; Flutter example и regression tests | Сложные инвентари, знания NPC и динамические LLM-сцены — только поверх; ранняя alpha API | **Пилот A, приоритет** |
| [ink_dart + flutter_ink](https://github.com/dennerkrans/ink_dart) | **MIT** с включёнными notices ink/inkjs/.NET (LICENSE) | Pure Dart + Flutter widgets | Полный runtime языка Ink: ветки/условия, списки, функции, переменные, теги, история, сохранения, controller/view/debug; тесты соответствия C# | Нужен отдельный компилятор `.ink` → JSON до запуска; сложный RPG-world и проверки изменений придётся выделить из Ink; модель BookWorld не совпадает с Ink напрямую | **Пилот B, очень перспективен** |
| [inkle/ink](https://github.com/inkle/ink) + [Inky](https://github.com/inkle/inky) | **MIT для ink runtime/compiler**; проверять дополнительные компоненты Inky перед поставкой | C# compiler, ink scripting language | Зрелый язык сценариев, авторские ветвления, переменные, выборы, генерация ink JSON через inklecate | Сам по себе не Flutter runtime; не анализирует автоматически произвольные книги | **Инструмент компиляции для пилота B** |
| [Narrat](https://github.com/liana-p/narrat-engine) | **MIT** | TypeScript + Vue + Pinia | RPG: инвентарь, квесты, характеристики, броски/проверки навыков, выборы, сейвы, скриптовые условия, локализация, UI | Не чистый Dart: прямое встраивание нарушит Flutter-first стек | **Эталон RPG-функций, не форкать целиком** |
| [Atrament Core](https://github.com/technix/atrament-core) + [Web UI](https://github.com/technix/atrament-web-ui) | **MIT** | JavaScript/inkjs + Preact | Режим читалки, темы light/dark/sepia, типографика, игровые сессии/слоты, checkpoints, история, выборы, аудио | Реализация web, не Dart; нужен JS runtime или перенос виджетов | **UX/сохранения как референс** |
| [SakiEngine](https://github.com/AimesSoft/SakiEngine) | **MIT** | Flutter/Dart + Rust | Полноценная визуальная новелла: чтение, ветки, откат, история, локализация, медиа, сборки Windows/Android/iOS, редактор | Большая платформа с зависимостью от Rust и специфического SKS-сценария; сложность интеграции выше | **Избирательно изучать UX, не брать целиком на M0** |
| [visual_novel_flutter](https://github.com/nomad-pixel/visual_novel_flutter) | **MIT** | Flutter/Dart | Компактные виджеты диалогов и выбора; YAML сцены, фон, музыка, прыжки | Проверенный `GameState` хранит только label/index/bg/ended; нет полноценной системы условий, RPG-state и сохраняемых причинных событий | **Для быстрого UI-прототипа** |
| [Zart](https://github.com/atebitftw/zart) | **MIT** | Dart, Flutter пример | Интерпретация классических игр Z-Machine/Glulx и вывод текстовых команд | Не компилятор книги в RPG и не основной runtime наших сценариев | **Позже: импорт сторонних IF-игр** |
| [Yarn Spinner](https://github.com/YarnSpinnerTool/YarnSpinner) | **MIT** | C# | Зрелые редакторские диалоги и скрипты | Нужен отдельный C# runtime/adaptor, не Dart | **Справочно** |
| [Narraitor](https://github.com/jerseycheese/Narraitor) | **MIT** | React/Next.js | Свободные действия, подсказки, навыки, инвентарь, журнал, браузерные сохранения | ИИ-центричный веб-проект, не базовый offline-classic движок | **Референс AI/гибридного UX** |
| [Text-Adventure-TUI](https://github.com/Theblackcat98/Text-Adventure-TUI) | **НЕ считать подтверждённой:** LICENSE содержит незаполненные [Year]/[Your Name] | Python + YAML + Ollama | Триггеры, игровые флаги, инвентарь, журнал, события, сохранения, разводит роль ИИ и правила | Python-terminal, ИИ; сомнения в атрибуции лицензии | **Не копировать до уточнения лицензии** |
| [text-quest-engine](https://github.com/bwizard94/text-quest-engine) | **LICENSE отсутствует** в проверенном корне | Python | Простая детективная RPG, флаги, предметы, доверие NPC, квесты, разные концовки, ввод команд/цифр | Маленький одnofайловый прототип, неподтверждённые права | **Идеи и тестовые сценарии, не копировать код** |

Данные об авторских правах относятся к исходникам проектов, не дают автоматически прав на сторонние книги, сценарии, игровые изображения и модельные веса.

## 2. Кандидат A: `story_engine` — почему он ближе к нашему BookWorld

**Проверено в коде:** `lib/src/runtime/story_engine.dart`, `lib/src/{condition,effect,transition,persistence,validation,format}`, `doc/STORY_FORMAT_V1.md`, `doc/API_GUIDE.md`, `test/`, `example/flutter_story_app/`.

- Сценарий определяется как `StoryProject` + `StoryEvent` + `StoryChoice`, с отдельными **условиями**, **эффектами** и **переходами**. Это соответствует принципу «LLM предлагает, детерминированный движок фиксирует последствия».
- Переменные только `bool,int,double,String`; для BookWorld требуются отдельные структуры инвентаря, знаний NPC, планов, временной шкалы, объектов и событий с независимыми транзакциями. Нельзя бездумно дублировать их в скалярные флаги движка.
- `StoryValidator`, versioned Story Format v1, независимые snapshot и восстановление — хорошие готовые решения. `StoryFormatBundle` **логический набор JSON**, а не ZIP/SQLite; наша оболочка `.bworld` может хранить этот сценарный формат как одну составную часть, не переименовывая Story Format v1.
- Seeded RNG и защитное ограничение автоматических переходов нужны для детерминированного повторения сценариев и защиты от бесконечных циклов.
- Документированы тесты сценариев на 100/500/1000 событий, но **эти тесты в нашем проекте не запускались**.
- **Риск**: `0.1.0-alpha.1`, Dart SDK `>=3.11.0`, репозиторий на момент просмотра имеет один публичный стартовый коммит; API до 1.0 может измениться. Пин версии обязателен.

**Закрепляемый SHA для воспроизведения анализа:** `f6cfe9110a75f9590e6eb54f503919be92a9421a`.

## 3. Кандидат B: `ink_dart` + `flutter_ink`

**Проверено:** `packages/ink_dart/README.md`, `pubspec.yaml`, тесты `test/conformance`, `packages/flutter_ink/{README.md,pubspec.yaml}`, `LICENSE`, upstream [ink](https://github.com/inkle/ink).

- Интерактивные истории с условными выборами, переходами, вычислениями, списками, переменными, функциями, тегами.
- API `Story.fromJson`, `continueStory`, `currentChoices`, `chooseChoiceIndex`, `state.toJson/loadJson`, `bindExternalFunction`.
- `flutter_ink` поставляет `StoryController`, `StoryView`, `StoryDebugView`; диалоги и варианты выбора можно визуально переопределить.
- Адаптированная история должна быть **скомпилирована в ink JSON заранее**. На Android нужно воспроизводить JSON, а не устанавливать C#-компилятор. Для компиляции `.ink` на Windows/в Python-инструменте можно использовать `inklecate` отдельным шагом.
- Ink не должен самостоятельно менять наши глобальные world/inventory/knowledge без проверки. `bindExternalFunction` разрешать только через явный whitelist и транзакционный слой; нельзя автоматически доверять сценарию или LLM.
- `ink_dart` использует Dart `^3.12.0`, Flutter-пакет заявляет Flutter `>=3.35.0`; проверить совместимость с выбранной Flutter stable и закрепить lockfile.
- Несмотря на то что GitHub API не распознал SPDX (NOASSERTION), **файл LICENSE прямо содержит MIT и notices портируемых ink/inkjs/.NET**.
- Версии source на момент аудита: `0.1.2` в `pubspec.yaml`; проверять опубликованную версию pub.dev отдельно при установке. Молодой проект (2026) — прототип обязателен.

**Закрепляемый SHA:** `a87f2ee1c1fbfc80f9f22483567fce91f133a18a`.

## 4. Готовые RPG-механики и визуальный слой

### Narrat — функциональный эталон
Репозиторий [liana-p/narrat-engine](https://github.com/liana-p/narrat-engine), подтверждён MIT. В описании и архитектуре реализованы:
- характеристики/XP/skill checks, предметы/инвентарь, квесты, условия, ветвящиеся диалоги, сохранения и локализация;
- магазины/награды и проверки навыков не обязательны для каждой книги; нужны **опциональные capability-пакеты**, чтобы роман о расследовании не превращался в боевую RPG.
- Полный форк потребовал бы Vue/TypeScript вместо согласованного Flutter/Dart — не рекомендуется.

**SHA:** `5ab42d5fcd798011770093e5148baffde2cbef6f`.

### Atrament — функции «электронной книги»
Два MIT-репозитория [core](https://github.com/technix/atrament-core) и [web UI](https://github.com/technix/atrament-web-ui) показывают: темы sepia/dark/light, выбор шрифтов, сохраняемые игровые сессии, checkpoints, named saves, подробную маркировку вариантов выбора, действия через Ink. Это хорошая **спецификация UX** для нашего читалкообразного интерфейса; JS/Preact нельзя просто перенести как Flutter-виджеты.

### Flutter компоненты
- [nomad-pixel/visual_novel_flutter](https://github.com/nomad-pixel/visual_novel_flutter) MIT: `lib/ui/widgets/{choice_box,dialogue_box}.dart`, `lib/services/script_{engine,loader}.dart`; очень лёгкий шаблон, но не полноценный Story Engine. **SHA:** `87238ae5c18f05dcd90de350d9386455c20aa42b`.
- [AimesSoft/SakiEngine](https://github.com/AimesSoft/SakiEngine) MIT: развитые Flutter UI и narration, auto/skip/history/rollback, медиа, редактор. Масштаб и Rust сервисы делают прямой форк рискованным. **SHA:** `a2987928a075e938acc00c7a6eccd23d0000aa8f`.

### Классические текстовые приключения
[Zart](https://github.com/atebitftw/zart) MIT — Dart-интерпретатор Z-Machine/Glulx с Flutter-проигрывателем. Можно позже добавить отдельный модуль импорта классических IF-файлов, **но это другая игровая платформа**, не наш формат BookWorld. Не смешивать интерфейсы сохранений без адаптера.

## 5. Практическое испытание M0: выбрать движок до M1

Оба кандидата должны получить **одинаковую** демонстрационную историю:
- >=8 сцен, >=10 условных/неусловных вариантов, два финала; три вида условий: флаг, наличие предмета, доверие к NPC;
- хотя бы одно событие, которого не должно происходить после альтернативного выбора (например, спасённый персонаж не числится погибшим);
- 20 ходов, сохранение посередине, восстановление, совпадение полного результата с непрерывным прохождением;
- проверки отсутствия неожиданной утечки скрытых знаний/спойлеров;
- тест 1000 сцен на чтение/валидацию/серийное выполнение (измерить на реальном Android и Windows);
- Flutter русский интерфейс: область чтения, выбор, журнал, сохранение, тёмная/сепия, системное открытие `.bworld`.
- режим AI выключен: никакого HTTP, Python, ключа, LLM или внешнего сервера.

### Что отдельно измерять
1. **Миграции формата**: наша внешняя `.bworld` и `.bwsave` — versioned, независимы от конкретного runtime. При смене движка пакет можно перекомпилировать; переход старых сейвов должен быть определён.
2. **Контроль мира**: может ли сценарный движок безопасно запросить/совершить проверяемое изменение инвентаря, знаний NPC и флагов без двойного владельца состояния?
3. **Ручной и AI-компилятор**: можно ли конвертировать одну схему события `BookWorld` в сценарий выбранного движка, не заставляя LLM генерировать невалидный исполняемый код?
4. **Переносимость**: одинаковые ID выбора, порядок событий, RNG, сейвы после перехода между Windows/Android.
5. **Размер пакетов и скорость**: холодный старт Android, размер рантайма, потребление памяти и латентность ввода (указать реальные тестовые устройства).

### Решение после M0
Если у `story_engine` достаточно стабильны сериализация, переходы и транзакции, выбрать его как базовый **скриптовый слой**, дополнив собственными типизированными RPG-доменами. Если ограниченные скалярные эффекты/невозможность интеграции мешают причинному миру, испытать `ink_dart` как основной диалоговый слой с чистым собственным правилами-сервисом. При несовместимости обоих допускается минимальный собственный Dart runtime, используя их тестовые идеи. **Не обещать прямой перенос без запуска прототипа.**

## 6. Границы лицензий
- MIT и BSD-3-Clause разрешают коммерческую модификацию/дистрибуцию при сохранении текстов лицензий/уведомлений.
- Отдельно проверять зависимости и авторские права контента, TTS, иллюстраций и исходных книг.
- У `Theblackcat98/Text-Adventure-TUI` шаблон LICENSE содержит незаполненные поля года/правообладателя: права на конкретный код юридически неопределённы, **не импортировать**.
- У `bwizard94/text-quest-engine` нет LICENSE в корне: **не копировать код**.
- Источники/испытания отслеживать в `THIRD_PARTY_RU.md`; при фактическом включении кода фиксировать `repository, revision, license, notices, files, modifications, tests`.

## 7. Официальные материалы кандидатов
- https://github.com/ErikSchultheiss/story_engine/blob/main/README.md
- https://github.com/ErikSchultheiss/story_engine/blob/main/doc/STORY_FORMAT_V1.md
- https://github.com/ErikSchultheiss/story_engine/blob/main/doc/API_GUIDE.md
- https://github.com/ErikSchultheiss/story_engine/blob/main/LICENSE
- https://github.com/dennerkrans/ink_dart/blob/main/packages/ink_dart/README.md
- https://github.com/dennerkrans/ink_dart/blob/main/packages/flutter_ink/README.md
- https://github.com/dennerkrans/ink_dart/blob/main/LICENSE
- https://github.com/inkle/ink
- https://github.com/liana-p/narrat-engine/blob/main/LICENSE
- https://github.com/technix/atrament-web-ui
- https://github.com/AimesSoft/SakiEngine
- https://github.com/nomad-pixel/visual_novel_flutter
- https://github.com/atebitftw/zart

**Итог аудита:** реалистично начать не с пустого runtime, а с тестового включения `story_engine` или `ink_dart`. Нельзя объявлять выбор окончательным, пока не пройден общий Android/Windows acceptance test.
