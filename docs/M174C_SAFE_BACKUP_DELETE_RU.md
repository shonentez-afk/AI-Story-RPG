# M1.7.4c1 — защита резервных копий и удаления
Статус: **PR #1 merged, CI #150 completed/success, 6/6 PASS** (2026-11-02).

Реализованы: exportBookworld с повторной криптографической/структурной проверкой архива; SQLite deleteBookworld с RESTRICT при наличии хотя бы одной кампании; deleteCampaign с обязательным полным replay и точной проверкой revision, удалением только выбранного журнала; дочерние fork-ветки независимы.
Flutter UI перед удалением требует подтверждение и успешный FilePicker.saveFile(bytes:...), для кампании — v2 .bwsave, для мира — исходный .bworld. При отмене диалога ничего не удаляется. Переход с экспортированным .bwsave v2 требует заранее установленного идентичного .bworld. Окно «Мои прохождения» остаётся единым.

Реальные Android/Windows запись на внешнем накопителе, повторный импорт, перенос между платформами и аварийное отключение питания пока SKIP. Никакой миграции M1.6 и изменений TXT/FB2 нет.
Тесты: два unit в campaign_manager; gateway и UI cancel в world_integration_test.dart. После исправления pumpAndSettle timeout успешны 80/80 Flutter тестов, Android debug APK и Windows portable в PR CI #150 (run 41374846035); итоговый squash в main a37eb21. Physical device E2E и recovery по-прежнему SKIP.


## M1.7.4c1 — окончательная автоматическая приёмка (2026-11-02)
- PR [#1](https://github.com/shonentez-afk/AI-Story-RPG/pull/1) merged в `main` как `a37eb21afe82e8e93dfc43fcb2caabe580153c6b` (squash), проверенный PR HEAD `13239eb843d99787ce50b5d97e71695be54dca85`.
- GitHub Actions [#150, run 41374846035](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41374846035) — **completed/success, 6/6 PASS**: Python, Dart, story_core/BookWorld, Flutter analyze и **80/80 tests**, Windows portable release bundle, Android debug APK. M0 SDK checks также PASS (run `41374846010`).
- Первый PR CI `41374617867` завершился Flutter **79 PASS / 1 FAIL** из-за `pumpAndSettle timed out` в `world_integration_test.dart` при подтверждении удаления: фоновый indeterminate progress indicator продолжает анимацию. Тест исправлен ожиданием конкретного кадра перехода диалога (300 ms), **не отключением проверки SQLite**. Повторный Flutter 80/80 PASS.
- Функции: обязательный системный backup перед удалением `.bwsave v2` или пустого `.bworld`, RESTRICT против удаления мира с кампаниями, проверка expectedRevision в SQLite, полный replay, сохранение дочерних fork. Старые M1.6 SharedPreferences/книги TXT/FB2 не затронуты.
- **SKIP:** реальный запуск на физических Android/Windows устройствах, восстановление из системного FilePicker после копирования файла, внезапная потеря питания, старые M1.6 migration, Book Compiler/AI. Результаты CI относятся к PR SHA; если после squash запущен отдельный main CI — его статус проверять по факту, не додумывать.
- Дальше **M1.7.4c2**: унификация ReaderChromeMode normal/reading/fullscreen в новом BookWorld UI, доступность 320dp/200%, Windows keyboard, затем Android↔Windows device E2E и backup restore QA. Не создавать вторую библиотеку и вторую CTA импорта книг.
