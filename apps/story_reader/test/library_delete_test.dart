import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('book deletion rejects arbitrary paths before accessing storage', () async {
    final storage = BookStorage();
    for (final invalid in ['../save.json', '/tmp/test.json', 'bad.json',
        '1_2.json/../save.json', '']) {
      await expectLater(storage.remove(invalid), throwsFormatException);
    }
  });
}
