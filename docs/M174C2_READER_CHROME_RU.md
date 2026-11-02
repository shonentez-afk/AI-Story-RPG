# M1.7.4c2 — единые читательские режимы подготовленной BookWorld RPG

Дата: 2026-11-02. Ветка: `feat/m174c2-bookworld-reader-chrome`.
**Автоматический CI принят**: GitHub Actions #155 (run 41376306932), 6/6 PASS, 83/83 Flutter PASS, Android и Windows PASS. Физические устройства ещё SKIP.

## Изменения

1. `WorldPlayPage` использует **тот же** `ReaderChromeMode` и `ReaderChromeButton`, что уже применяются для чтения книги и пилотной RPG. Никакой второй системы игровых экранов или отдельной библиотеки не добавлено.
2. **Обычный режим:** заголовок/кнопки настроек и обновления, меню режимов в AppBar и нижняя панель «Герой / Предметы / Журнал».
3. **Режим чтения:** заголовок скрывается, панель героя остаётся, выборы и сцена остаются интерактивны, плавающая кнопка возвращает управление.
4. **Полный экран (интерфейса):** скрываются AppBar и игровая панель, текст/варианты выбора видны и работают; касание неинтерактивного текста включает/скрывает панель; FAB остаётся для выхода/выбора режима. Это **не** перевод окна Windows в нативный exclusive fullscreen.
5. **Windows-клавиатура:** F11 включает или отключает полный экран игры; Esc в режиме чтения/полном экране возвращает обычный режим; Tab/Shift+Tab/Enter остаются стандартными Flutter средствами доступа к кнопкам. Не перехватывать Esc в обычном режиме, чтобы не ломать диалоги.
6. **Единые настройки:** `ReadingSettingsStore` и `ReadingSettingsSheet` из старой читалки применяются к новым сценам: палитра светлая/сепия/тёмная/OLED, размер шрифта, межстрочный интервал и боковые поля. Настройки локальны и не зависят от ИИ. При недоступности preferences сохранён безопасный default.
7. **Границы безопасности:** переключение режимов и оформления не пишет в SQLite, не создаёт игровых ходов, не меняет `GameProgress`, `CampaignStore`, `SaveStore`, `pilot_save_codec`, `.bwsave` v1/v2 или импорт TXT/FB2/.bworld. SQLite commit-on-choice сохраняется без изменения.

## Новый QA

`apps/story_reader/test/world_integration_test.dart`:
- проверка общей тёмной читательской палитры и восстановления оформления после повторного открытия BookWorld, SQLite revision без изменений;
- переход normal → reading → fullscreen, F11/Esc, раскрытие журнала по касанию сцены, запрет заблокированного варианта, подтверждённый SQLite ход;
- адаптивность 320dp/200%, полноэкранная кнопка выбора и повторный возврат к AppBar.
- Существующий 35-ходовый UI replay после 23, failing-write, backup/delete, legacy M1.6 и обе платформы остаются в обязательном CI.

## Ограничения / следующие проверки

- Физический TalkBack/Narrator, Windows Tab-цепочка с реальным оборудованием и пиксельные скриншоты: **SKIP до устройства**.
- Настоящая OS-level полноэкранность Windows, EPUB, мобильный Book Compiler, AI/HYBRID, физический Android ↔ Windows .bwsave v2 transfer не реализованы.
- CI завершён и подтверждён. Исходный SHA после squash в main: `db7ec972a8fbbcb391a3d5cbd710154250eebe94`; PR #155 проверял `b2e7f2f`. Flutter 83/83, обе платформенные сборки PASS.
- Далее: M1.7.4c3 физическая E2E-матрица Android+Windows (проверить FilePicker backup/restore, BookWorld ZIP и SQLite), миграционная политика legacy M1.6 без перезаписи, затем M2 Book Compiler.


## M1.7.4c2 — автоматическая приёмка ЗАКРЫТА (2026-11-02)

- PR [#2](https://github.com/shonentez-afk/AI-Story-RPG/pull/2) merged/squash в `main`: **кодовый SHA `db7ec972a8fbbcb391a3d5cbd710154250eebe94`**; проверенный PR HEAD `b2e7f2fbf41574d511646b486d8afe14da34e5bd`.
- GitHub Actions [#155 (run `41376306932`)](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41376306932): **completed/success, 6/6 jobs PASS**. Python PASS, Dart PASS, story_core/schema/BookWorld PASS, Flutter analyze PASS, **Flutter 83/83 tests PASS**, Android debug APK PASS, Windows portable release + полный bundle PASS. Присутствуют артефакты `AI-Story-RPG-Android-debug`, `AI-Story-RPG-Windows-portable` и `AI-Story-RPG-BookWorld-demo` (проверять время хранения в Actions).
- В промежуточном CI #152 Flutter analyze FAIL: лишний `dart:typed_data` import после `flutter/services.dart`, удалён. CI #153 Flutter widget FAIL 4: после прокрутки новая сцена оставляла бейдж хода вне видимой области и при 200% кнопка была частично за пределами viewport. **Исправлено в реализации**: `WorldPlayPage` прокручивает к началу сцены после попытки выбора (успешной либо отказанной), но переключение chrome не сбрасывает позицию; тест 200% дополнительно прокручивает кнопку целиком в экран. Проверки не отключались. #154 cancelled при более новом коммите.
- Итог: общие `ReaderChromeMode` normal/reading/fullscreen, ReaderChromeButton, ReadingSettingsStore/Sheet, меню в AppBar, F11/Esc, доступные кнопки выбора/показа Hero/Items/Journal и общий офлайн palette/font/spacing. **Не изменён** `BookworldCampaignStore`, `StoryRuntimeAdapter`, журнал SQLite, TXT/FB2, M1.6 `CampaignStore/SaveStore/GameProgress` и .bwsave v1/v2.
- **SKIP:** физический Android/Windows UI и реальный F11/Esc/Tab/Enter на ПК, TalkBack/Narrator, native window fullscreen, межплатформенный импорт/экспорт на устройствах, power-failure, миграция legacy M1.6, Book Compiler/AI. CI-сборка ≠ проверка аппаратных устройств.
- **СЛЕДУЮЩИЙ ШАГ M1.7.4c3:** физическая Android↔Windows E2E-матрица (открыть .bworld, сделать 20+ ходов, резервная копия .bwsave v2, восстановление с exact world sha, перезапуск, forks, отмена удаления, keyboard/TalkBack/Narrator), затем политика безопасной миграции M1.6. Для автоматических тестов можно дополнительно построить cross-platform fixture-экспорт; не объявлять физические тесты PASS без пользователя/оборудования. После M1 acceptance — M2 Book Compiler.
