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
