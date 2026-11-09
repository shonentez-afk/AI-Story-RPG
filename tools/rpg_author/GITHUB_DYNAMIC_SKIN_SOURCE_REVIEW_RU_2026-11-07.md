# Проверенные GitHub-источники для индивидуального скина каждой книги

Дата: 7 ноября 2026. Статус: исследование, не реализация. Дополнение к [PER_BOOK_DYNAMIC_SKIN_DESIGN_RU_2026-11-07.md](PER_BOOK_DYNAMIC_SKIN_DESIGN_RU_2026-11-07.md) и [генеральному плану](AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md). Исходники и лицензии проверены в публичных GitHub-репозиториях. Текущий main = 81fb75b77f11b8f82cafa1e7604afa9fe9bbb678. Native Flutter, BookWorld и main из внешней ветки только читаем.

## 1. Основные технические источники — что брать и где

| Приоритет | Проект и точное место | Что работает у авторов | Что внедрить у нас | Лицензия / риски |
| --- | --- | --- | --- | --- |
| A1 | [game-hud](https://github.com/threejsassets/game-hud), [12 skin CSS](https://github.com/threejsassets/game-hud/tree/main/dist/skins), [fantasy.css](https://github.com/threejsassets/game-hud/blob/main/dist/skins/fantasy.css) | 12 тем поверх одного набора HUD/диалогов/инвентаря; переменные palette, panel, button, slot, outline и scene | **Главный архитектурный образец**: immutable semantic UI + theme tokens + единый runtime. 12 семейств как ориентир, не обязательный объём релиза | MIT, проверен корневой LICENSE; HTML/CSS в Flutter не запускать |
| A2 | [Flame](https://github.com/flame-engine/flame), [NineTileBox](https://github.com/flame-engine/flame/blob/main/packages/flame/lib/src/nine_tile_box.dart), [NineTileBoxComponent](https://github.com/flame-engine/flame/blob/main/packages/flame/lib/src/components/nine_tile_box_component.dart) | 9-slice растягиваемые рамки без искажения углов: окна, диалоги, панели | Собственный ThemedFrame / ThemedDialogueBox на Flutter Canvas; не добавлять весь Flame ради рамок | MIT, подтверждён |
| A3 | [PixelForge](https://github.com/KodoRe/pixel-forge), [движок](https://github.com/KodoRe/pixel-forge/blob/main/pixel-forge.js), [JSON API](https://github.com/KodoRe/pixel-forge/blob/main/README.md) | JSON → seeded персонажи/предметы/иконки/тайлы/здания; palette presets, layers, animations | Общий пиксельный recipe/seed для сцены, NPC, иконок и UI, генерировать данные, не JS | **ВНИМАНИЕ:** README заявляет MIT и ссылается на LICENSE, но в корне LICENSE нет, repo metadata license=null. Заимствовать идею, пока права на код/арт не подтверждены |
| A4 | [Material Color Utilities](https://github.com/material-foundation/material-color-utilities), [Dart source](https://github.com/material-foundation/material-color-utilities/tree/main/dart/lib), [scheme guide](https://github.com/material-foundation/material-color-utilities/blob/main/dev_guide/creating_color_scheme.md) | Исходный цвет → tonal palette/light/dark/contrast scheme, роли текста и поверхностей | Автоматическая тематическая палитра книги, контрастные варианты и существующие пользовательские настройки чтения | Apache-2.0 в LICENSE/pubspec; учитывать notices |
| A5 | [LovecraftUI](https://github.com/Loresong-Game/LovecraftUi), [theme.js](https://github.com/Loresong-Game/LovecraftUi/blob/main/src/theme.js), [texgen.js](https://github.com/Loresong-Game/LovecraftUi/blob/main/src/texgen.js), [art.js](https://github.com/Loresong-Game/LovecraftUi/blob/main/src/art.js), [themes](https://github.com/Loresong-Game/LovecraftUi/tree/main/src/themes) | Процедурные фактуры/орнаменты без обязательных PNG, единые токены, проверка resize, focus | Библиотека безопасных декоративных рецептов (камень, пергамент, металл, неон) и audit всех состояний; **не WebGL/three.js** | MIT в корневом LICENSE, metadata Other; ассеты проверять отдельно; молодой проект |
| B1 | [BlockUI](https://github.com/malilion/BlockUI), [themes](https://github.com/malilion/BlockUI/tree/main/packages/themes), [tokens](https://github.com/malilion/BlockUI/tree/main/packages/tokens), [components](https://github.com/malilion/BlockUI/tree/main/packages/react), [E2E tests](https://github.com/malilion/BlockUI/tree/main/tests/e2e) | 5 тем над InventoryGrid/QuestCard/PlayerHUD, mobile responsive, disabled/hover/focus, a11y проверки | Шаблоны inventory slots, hero cards, журнал заданий, матрица UI состояний и golden/widget tests | **Несогласованная лицензия:** root LICENSE/NOTICE — Apache-2.0, README и packages/*/LICENSE — MIT. Код/графику не копировать до выяснения лицензии конкретного файла |
| B2 | [Godot Theme Editor](https://github.com/godotengine/godot-docs/blob/master/tutorials/ui/gui_using_theme_editor.rst), [theme override code](https://github.com/godotengine/godot/blob/master/scene/gui/control.cpp) | Theme как ресурс, наследование и overrides для разных UI типов, live preview | SkinPack data resource, безопасный fallback и независимые роли элементов. Реализовать в Flutter ThemeExtension | Godot MIT, не внедрять Godot runtime |
| B3 | [RenPy GUI](https://github.com/renpy/renpy/blob/master/sphinx/source/gui.rst) | Отдельные стили narrator, speaker, history, preferences, save/load и navigation screens | Стилевые роли вместо замены диалоговой логики и сохранений | Только UX-ориентир, не импортировать RenPy код/изображения |
| B4 | [NES.css](https://github.com/nostalgic-css/NES.css), [SCSS components](https://github.com/nostalgic-css/NES.css/tree/develop/scss/components), [pixel icons](https://github.com/nostalgic-css/NES.css/tree/develop/scss/icons) | 8-bit кнопки, контейнеры, badges/иконки в единой системе | Один style archetype retro_pixel, простой CustomPainter; не заменять кириллический шрифт ASCII-font | Код MIT; шрифты требуют отдельной лицензии и кириллицы |
| B5 | [Pixel UI Fantasy Free](https://github.com/Spyridon-Pikoulas/godot-pixel-ui-fantasy-free), [theme и slices.json](https://github.com/Spyridon-Pikoulas/godot-pixel-ui-fantasy-free/tree/main/addons/pixel_ui_fantasy/themes) | Профессионально сгруппированный parchment style: 9-slice windows, buttons, item slots, quest, иконки | Готовый источник вдохновения для старой сказки/фэнтези и размеры декоративных слоёв, а не обязательная библиотека | CC BY 4.0: для копирования реальных PNG обязательна атрибуция; font в наборе ASCII/Latin-1 и не годится для русского текста |
| B6 | [Pixelorama](https://github.com/Orama-Interactive/Pixelorama), [палитры JSON](https://github.com/Orama-Interactive/Pixelorama/tree/master/pixelorama_data/Palettes) | Layers, indexed palettes, frame animation, pixel art QA | Ориентир для единой пиксельной палитры и просмотра sprite states; редактор не нужен пользователю | MIT у кода, отдельно проверять условия третьесторонних артов |

## 2. Какие идеи объединить в один движок

**Theme Architecture = game-hud + BlockUI + Godot.**
Одна Flutter-компонентная структура: Hero, Items, Journal, Dialogue, TextWindow, Choice, Save, Menu. К ней подключается versioned ThemePack с ограниченными токенами (surface, ink, accent, stroke, shadow, button-state, dialog-nameplate, icon-role), а не разные интерфейсные движки. Semantic action IDs и расположение критических кнопок неизменны.

**Art Direction = PixelForge + LovecraftUI.**
После полного анализа книги появляется один StyleBible: mood, эпоха (только при наличии источника), орнаменты, набор материалов, style_seed, персонажные appearance seeds, 2–4 акцента. И из него согласованно выводятся пиксельные сцены, обрамление текста, предметные карточки, персонажные рамки и иконки. Все процедурно, без обязательного PNG и без скрипта на каждую книгу. Для нового названия книги нельзя просто случайно менять палитру: визуальные решения должны быть сюжетно осмысленными.

**Frames = Flame NineTileBox + Pixel UI Fantasy.**
Окно текста/диалогов/героя/предметов растягивается при 100–200% масштабе и русских длинных строках. Углы не деформируются, важные кнопки не срезаются, орнамент не лежит под текстом.

**Colors & readability = Material Color Utilities.**
Скин обязан допускать override light/sepia/dark/OLED, высокий контраст, увеличение текста и reduced motion. Пользовательские настройки всегда важнее автогенерации.

**Dialog & journal = RenPy.**
Стилизовать storyteller, speaker-name, choice/history/quest/result отдельно, но всю семантику брать из наших SceneDialogueStage/WorldGameView/StoryWorld. Скин не открывает секреты NPC, не порождает WorldEvent и не изменяет сохранения.

## 3. Предлагаемая техническая цепочка

BookEvidenceGraph → BookStyleEvidence (source-backed genre, tone, motifs) → StyleBibleV1 (palette, material, style_seed, contrast) → PixelSceneRecipe + UIThemeRecipeV1 → Python JSON schema checks / archive limits → будущий единый vNext .bworld с capability → Dart Flutter ThemeExtension и CustomPainter.

Имена логических новых модулей:
- внешний генератор: BookStyleEvidenceCollector, StyleBibleCompiler, SkinRecipeComposer, SkinQA;
- будущий Flutter: BookThemePack, ThemeExtensionAdapter, BookFramePainter, SemanticIconPainter, GamePanelSkinAdapter;
- script/writer/schema только после формального versioned/native соглашения; main rich v3 содержит строго четыре ZIP entries.

**Один игровой world state, никаких эффектов в скине.** Стиль меняется от книги к книге, но не случайно при каждом запуске; явный reroll стиля создаёт новую cosmetic revision, не новый campaign/save identity.

## 4. Реализация пакетами и приёмка

**P0:** заканчивать реальный полный FB2 → работающую текстовую RPG на Android/Windows, без блокировки визуализацией.

**P1 prototype, только внешний автор:** один StyleBible и три синтетических тематических профиля (fairytale_parchment, detective_archive, neon_cyberpunk), JSON Schema и тесты детерминизма/контраста/отказа на неизвестных полях; preview как приватный sidecar, НЕ как готовый v3 импорт.

**P2 вместе с пиксельными сценами:** один согласованный функциональный пакет Python writer/verifier + Dart importer + Flutter renderer. В одном будущем .bworld — pixels + style_bible + skin, с лимитами CPU/RAM/архива, offline, fallback, Android portrait/landscape и Windows DPI 150%, Cyrillic scale 200%, golden screenshots и SQLite replay. Не отдельный PR на каждую рамку.

**Лицензионный gate:** перед копированием алгоритма/иконки/PNG нужно закрепить upstream SHA, файл, корректный LICENSE/NOTICE, атрибуцию и совместимость с лицензией AI Story RPG. Репозиторий на GitHub сам по себе не даёт права копировать содержимое. Противоречивые лицензии и PixelForge без LICENSE означают «используем только принципы», пока вопрос не решён.

## 5. Решение для AI Story RPG

Первый архитектурный референс — game-hud (12 стилей на одном интерфейсе). Для реального Flutter renderer использовать Flutter ThemeExtension + Material Color Utilities; для рамок при необходимости взять NineTileBox идею из Flame; для графики — типизированные seeded recipes по идеям PixelForge/LovecraftUI, не копируя чужой runtime. Проверять UX по BlockUI/NES.css/RenPy, ограничивать assets и все действия по нашему native runtime. **Одна книга → один автоматически сгенерированный единый дизайн всей игры, один .bworld, без пересборки APK.**
