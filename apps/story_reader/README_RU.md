# M1: «Живая книга» — Flutter host, первый срез

Основной runtime: `story_engine: 0.1.0-alpha.1` (ADR-001). Сейчас здесь исходный код Flutter читателя: текст сцен, выбор, перезапуск и локальные сохранение/восстановление между запусками через `StoryRuntimeSnapshotCodec`.

**Ещё не реализовано:** полноценный формат .bwsave и несколько слотов, книга из FB2/EPUB, AI, `.bworld/.bwsave`, Android/Windows generated files, готовые инсталляторы.

На компьютере с установленным Flutter:

```sh
cd apps/story_reader
flutter create --platforms=android,windows .
flutter pub get
flutter analyze
flutter test
flutter run
```

Для сборки Windows нужен Windows host + Visual Studio C++; Android — Android SDK. Команда `flutter create` с точкой создаст отсутствующие платформенные директории, не заменяя существующий `lib/main.dart` (перед запуском сохранить рабочую копию). Исходные файлы размещены в GitHub; их сборка пока не подтверждена.

## Первый Android APK через CircleCI

В `.circleci/config.yml` добавлен job `android-apk` на Android CI образе. На runner создаётся стандартный каталог `android/` командой `flutter create --platforms=android --project-name ai_story_reader --org com.aistoryrpg .`, затем выполняется `flutter build apk --debug`. Результат сохраняется как CircleCI artifact `ai-story-rpg/android/AI-Story-RPG-M1-debug.apk`; рядом лежит `SHA256SUMS.txt`.

Для получения APK: CircleCI → Pipeline ветки `main` → `android-apk` (зелёный) → Artifacts → `AI-Story-RPG-M1-debug.apk` → скачай и открой на Android. Установка из неизвестного источника может потребовать разрешения ОС. **Debug APK только для внутреннего тестирования, не для публикации в Google Play**.

**Состояние:** job добавлен, но его прохождение и существование APK до первого зелёного запуска **не подтверждены**. При падении передай журнал первого красного шага. Файлы Android генерируются на CI и пока не коммитятся в репозиторий; позднее зафиксируем их для воспроизводимых production builds.
