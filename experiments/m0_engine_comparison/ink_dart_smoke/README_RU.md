# M0: ink_dart smoke

Проверяет реальный пакет `ink_dart` на скомпилированном Ink JSON. Не подменяет проверку Ink обработкой собственного JSON сценария.

1. `python3 ../pilot/compile_pilot.py` создаёт `manor_mystery.ink`.
2. `inklecate -o ../pilot/manor_mystery.ink.json ../pilot/manor_mystery.ink` компилирует исходник (компилятор устанавливается отдельно).
3. `dart pub get`, `dart analyze`, `dart run bin/smoke.dart ../pilot/manor_mystery.ink.json` проверяют воспроизведение, выбор и сохранение.

Официальный `inklecate` необходим: пакет `ink_dart` не компилирует исходный Ink. CircleCI выполняет Dart smoke после получения компилятора; до такого шага тест не считается пройденным.
