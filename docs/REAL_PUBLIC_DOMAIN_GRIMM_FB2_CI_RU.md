# Полная, обязательная FB2-регрессия по сказкам братьев Гримм

Дата: 2026-11-03. **PR #51 MERGED / exact-head CI PASS**; код main `12f45882e34830632e6f8fb385d94c833874c1cd`; проверенный PR HEAD `f517af0e5dc49db621d27d234c60ff4e6c841234`.

## Почему раньше было 2 SKIP

Пропускались **НЕ** произведения братьев Гримм. Два давних теста обращаются к конкретным **личным FB2 Андерсена**:

- `private_real_fb2_smoke_test.dart` — `04_Svinopas.fb2`;
- `private_andersen_five_books_test.dart` — ещё пять FB2, в том числе «Снежная королева».

Их файлов нет на публичных runners. `SKIP` означал отсутствие входных файлов, не сомнения в возрасте оригинала. Эти тесты остаются обязательными при наличии входных файлов в локальном запуске, иначе честно показывают SKIP. Нельзя без файла подменить реальную проверку ложным PASS.

## Новый обязательный real-book CI (нет SKIP)

Создано `tools/build_grimm_public_domain_fb2.py`, без Python-зависимостей. CI **скачивает весь исторический текст** #2591 `Grimms' Fairy Tales` по HTTPS от Project Gutenberg (переводы Edgar Taylor / Marian Edwardes), выделяет **все 62 настоящие сказки и их полные абзацы**, генерирует валидный FB2 с двумя авторами и подробный SHA-256 manifest.

Перед использованием проверяются START/END-маркеры Gutenberg, редакция, оглавление, точный список 62 глав, полнота более 280 тысяч символов и 500 абзацев. Любое отсутствие полной книги, ошибочный раздел или недоступная загрузка = **FAIL**, не сокращённая заглушка и не SKIP. Исходный текст, полученный FB2 и manifest хранятся только в workspace GitHub runner; не в commit, release, логах содержимого, приложении, игре или сетевом промпте.

`public_domain_grimm_full_fb2_test.dart` проверяет на настоящем многостраничном FB2:
1. Полный парсинг 62 глав / заголовков / авторов, источник объёма и SHA-256;
2. Индексирование и покрытие текста, координаты, отсутствие выпадений;
3. Семантические окна по главам, строгие границы и восстановление пустой приватной очереди ИИ без каких-либо сетевых вызовов;
4. Полный локальный проход OfflinePreparationCoordinator, атомарные контрольные точки names/narrative/catalog, детерминированный повторный запуск и валидность цитат;
5. Сохранение оригинальной книги в приватной библиотеке, повторный импорт и совпадение source fingerprint.

Тест **запускается как часть обычной Flutter CI, без пометки skip**. Переменные `AI_RPG_GRIMM_PUBLIC_FB2_PATH` и `AI_RPG_GRIMM_PUBLIC_MANIFEST_PATH` обязательны; без созданного корпуса тест падает с понятным сообщением. Историческое издание **без иллюстраций**; отдельные тесты FB2 с 67 изображениями и исходные пользовательские иллюстрированные FB2 сохраняются, а не подменяются текстовым корпусом.

### Запуск вручную Windows / Linux

Из корня репозитория:

```bash
python3 tools/build_grimm_public_domain_fb2.py \
  --output apps/story_reader/test/fixtures/grimm_ci.fb2 \
  --manifest apps/story_reader/test/fixtures/grimm_ci.json
cd apps/story_reader
export AI_RPG_GRIMM_PUBLIC_FB2_PATH=test/fixtures/grimm_ci.fb2
export AI_RPG_GRIMM_PUBLIC_MANIFEST_PATH=test/fixtures/grimm_ci.json
flutter test test/public_domain_grimm_full_fb2_test.dart --reporter expanded
```

Для Windows PowerShell вместо `export` использовать `$env:AI_RPG_GRIMM_PUBLIC_FB2_PATH=... ` и аналогично manifest. При наличии заранее проверенной локальной редакции можно использовать `--input <путь-к-2591.txt>` без скачивания.

## Авторские права и ограничения

Братья Гримм жили в XIX веке: оригинальные произведения в общественном достоянии. Выбранные английские исторические переводы старые; Project Gutenberg указывает public-domain status в США (https://www.gutenberg.org/ebooks/2591). Но конкретный **современный русский перевод**, редакторские добавления и новые иллюстрации могут иметь отдельных правообладателей, даже если тесты и игра некоммерческие. Поэтому пользовательские иллюстрированные FB2 не выкладываются в открытый GitHub автоматически.

Этот английский корпус — честный **полный технический FB2/индексационный/stress тест**, а не доказательство качественного *русскоязычного* понимания всех событий, характеров, алиасов, секретов и причинности ИИ. Русские сценарные тесты / пользовательские FB2 и физический Windows+Android E2E нужны отдельно.

## QA gate

- Python генератор: негативные тесты отбрасывают неполный текст и незнакомое издание.
- GitHub Actions: `reference-tests`, `dart-sdk`, `story-core`, `flutter-reader` (вкл. полный настоящий Grimm FB2), `windows-exe`, `android-apk` и `M0`.
- До exact-head CI — **CODE/PENDING**. После CI указать SHA, run IDs, реальные PASS/FAIL/SKIP. Не путать CI с пользовательским UX по своей конкретной книге.

Следующий этап M2f3b: согласованная обработка окон на реальных русских FB2 и контроль смысловых ошибок, объединения персонажей и хронологии. Свободная RPG не включается автоматически.

## Принятие PR #51 — фактические результаты GitHub Actions

- PR: https://github.com/shonentez-afk/AI-Story-RPG/pull/51 ; **MERGED** squash `12f45882e34830632e6f8fb385d94c833874c1cd`.
- Exact проверенный HEAD: `f517af0e5dc49db621d27d234c60ff4e6c841234`.
- GitHub Actions **41663754137 COMPLETED/SUCCESS 6/6**: Python reference PASS; Dart engine PASS; BookWorld/SQLite PASS; Flutter analyze PASS и **347 PASS / 2 private Andersen SKIP**; Windows portable PASS; Android debug APK PASS. Дополнительный M0 **41663754133 COMPLETED/SUCCESS**.
- В логе `Build real COMPLETE public-domain Grimm FB2` подтверждены **62 настоящие сказки, 909 абзацев, 514 890 символов**. SHA256 Gutenberg plaintext `377ebb8ca06cd8bc0b1015ddb54766c44f50dece731c53bb030f1cc00f54092a`, полученного FB2 `1273bc9b20bd1a5cdccdbb29489ba0962521539903898f1ae726a376089ca038`.
- Два новых Dart-теста по полной книге **PASS**: все 62 главы, exact source index, windows, private Z.ai queue, full offline preparation, durable checkpoint replay, BookStorage persist/reopen. Никакой сетевой ИИ книги в тестах не запускался.
- Во время первого CI `41663507607` Flutter analyze FAIL на один unused import; он был убран в commit `f517af0e`; только финальный exact-head CI принят.
- Пост-merge main CI и публикация нового тестового релиза требуют отдельной проверки; физические Windows/Android real-device E2E не превращаются автоматически в PASS.
