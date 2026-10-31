# Настройка Dart и Flutter для AI Story RPG (Windows + Android)

**Обновлено:** 2026-11-01. **Dart отдельно устанавливать не нужно** — Flutter SDK включает Dart SDK. В ChatGPT облачная рабочая среда временная; установки там не сохраняются между запусками. Из среды проекта проверено: `git` установлен, `dart` и `flutter` отсутствуют; прямой доступ `git ls-remote https://github.com/flutter/flutter.git` завершился `Could not resolve host`. Поэтому здесь SDK нельзя скачать обычной командой.

## Способ A: собственный Windows ПК — предпочтительный для сборки Windows + Android

1. Поставить **Git for Windows**: https://git-scm.com/download/win.
2. Поставить **Visual Studio Code**: https://code.visualstudio.com/.
3. В VS Code установить расширение **Flutter** (оно установит и Dart extension) и через командную палитру выбрать `Flutter: New Project`. Если SDK не найден, выбрать `Download SDK`; расположить его, например, в `C:\src\flutter`.
4. После установки убедиться, что `C:\src\flutter\bin` добавлен в пользовательский PATH и **перезапустить терминал**.
5. Поставить **Android Studio**, в SDK Manager установить рекомендуемые Android SDK Platform, Build Tools, Command-line Tools, Emulator (для физического телефона эмулятор необязателен). При настройке принять лицензии.
6. Поставить **Visual Studio 2022 / актуальную Visual Studio** с компонентом `Desktop development with C++` и нужными Windows SDK и C++ CMake tools; **VS Code не заменяет Visual Studio C++ build tools** для сборки Windows EXE.
7. Открыть PowerShell, выполнить:

```powershell
flutter --version
dart --version
flutter doctor -v
flutter doctor --android-licenses
flutter devices
```

Устранить ошибки `flutter doctor` именно по целевым платформам Android и Windows.

Далее клонировать проект:

```powershell
git clone https://github.com/shonentez-afk/AI-Story-RPG.git
cd AI-Story-RPG
python experiments/m0_engine_comparison/pilot/compile_pilot.py
python -m unittest discover -s experiments/m0_engine_comparison/tests -v
```

**Важно:** Flutter-приложение ещё не создано; `flutter build apk` и `flutter build windows` нельзя запускать успешно, пока в репозитории не появится готовый `apps/story_reader` с `pubspec.yaml`, `android/`, `windows/` и исходниками.

После появления приложения:

```powershell
cd apps/story_reader
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build windows --release
```

## Способ B: GitHub Actions — SDK в отдельной среде сборки

Файл `.github/workflows/m0-sdk-and-tests.yml` автоматически устанавливает Flutter stable (со встроенным Dart) **в GitHub Actions runner** и запускает `flutter doctor -v`, а также Python-тесты сценария. Запускается через **Actions → M0 SDK and reference checks → Run workflow** либо после push в main.

Это не устанавливает Flutter на личный компьютер и **не делает Flutter доступным в ChatGPT**. Фактический результат смотреть в Actions: до запуска статусы `PASS` не заявлять. При исчерпании квоты GitHub Actions использовать локальный ПК или собственный CI-раннер.

Для последующей настоящей сборки Windows нужен Windows runner с установленным компилятором Visual Studio; для Android — установленный Android SDK. Текущий job SDK-check этого не обещает.

## Способ C: чистый Linux / собственный сервер

```sh
git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"
flutter --version
dart --version
flutter doctor -v
```

В постоянной системе `PATH` следует добавить в `~/.profile` (или конфигурацию своей оболочки). Для сборки Android отдельно нужны Android SDK/JDK и настройки `ANDROID_HOME`; **с Linux нельзя собрать нативный Windows EXE** через `flutter build windows` — для Windows нужен Windows host.

## Версии движков для сравнения M0

- `story_engine`: исходный пакет требует Dart SDK `>=3.11.0 <4.0.0`, ранняя alpha; сравнение возможно только с подходящим Flutter/Dart.
- `ink_dart`: исходный пакет требует `^3.12.0`; `flutter_ink` — Flutter `>=3.35.0`. Выбранный Flutter stable **проверить на совпадение SDK constraints**. Не обходить несовместимость через принудительную правку чужих зависимостей.
- Для `.ink -> compiled ink JSON` нужен компилятор Ink (`inklecate`) на машине подготовки. Dart runtime на телефоне компилировать Ink не обязан.

## Официальные инструкции

- Flutter: https://docs.flutter.dev/install
- Windows: https://docs.flutter.dev/platform-integration/windows/setup
- Android: https://docs.flutter.dev/platform-integration/android/setup
- PATH: https://docs.flutter.dev/install/add-to-path
- SDK versions: https://docs.flutter.dev/install/archive
- Dart SDK: https://dart.dev/get-dart
