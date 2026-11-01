import 'dart:convert';
import 'dart:typed_data';
import 'package:xml/xml.dart';

class ImportedBook {
  const ImportedBook({
    required this.title,
    required this.author,
    required this.chapters,
    this.cover,
  });

  final String title;
  final String author;
  final List<String> chapters;
  final Uint8List? cover;

  String get text => chapters.join('\n\n');
}

class BookImporter {
  static ImportedBook parse(String filename, Uint8List bytes) {
    if (bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('Максимальный размер книги — 20 МБ');
    }
    final ext = filename.split('.').last.toLowerCase();
    if (ext != 'txt' && ext != 'fb2') {
      throw const FormatException('Поддерживаются TXT и FB2');
    }
    String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const FormatException(
        'Пока поддерживается кодировка UTF-8. '
        'Для других кодировок нужен отдельный декодер.',
      );
    }
    if (ext == 'txt') {
      final body = text.replaceFirst('\ufeff', '').trim();
      if (body.isEmpty) throw const FormatException('Файл пуст');
      return ImportedBook(
        title: filename.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        author: '',
        chapters: [body],
      );
    }
    return _fb2(text, filename);
  }

  static ImportedBook _fb2(String source, String filename) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(source);
    } on XmlException {
      throw const FormatException('Неверный XML в файле FB2');
    }
    Iterable<XmlElement> child(XmlElement? node, String local) =>
        node == null
            ? <XmlElement>[]
            : node.children.whereType<XmlElement>().where(
                (e) => e.name.local == local,
              );
    XmlElement? first(XmlElement? node, String local) {
      for (final e in child(node, local)) {
        return e;
      }
      return null;
    }

    final root = document.rootElement;
    if (root.name.local != 'FictionBook') {
      throw const FormatException('Файл не является FB2');
    }
    final description = first(root, 'description');
    final titleInfo = first(description, 'title-info');
    final title = first(titleInfo, 'book-title')?.innerText.trim();
    final authors = child(titleInfo, 'author').map((author) {
      return ['first-name', 'middle-name', 'last-name']
          .map((part) => first(author, part)?.innerText.trim() ?? '')
          .where((part) => part.isNotEmpty)
          .join(' ');
    }).where((author) => author.isNotEmpty).join(', ');

    Uint8List? cover;
    final coverPage = first(titleInfo, 'coverpage');
    final coverRef = first(coverPage, 'image');
    String? id;
    if (coverRef != null) {
      for (final attr in coverRef.attributes) {
        if (attr.name.local == 'href') {
          id = attr.value.startsWith('#') ? attr.value.substring(1) : null;
          break;
        }
      }
    }
    if (id != null) {
      for (final binary in child(root, 'binary')) {
        if (binary.getAttribute('id') != id) continue;
        try {
          final raw = base64.decode(binary.innerText.replaceAll(RegExp(r'\s'), ''));
          // Bound memory and only render genuine PNG/JPEG image headers.
          if (raw.isNotEmpty && raw.length <= 8 * 1024 * 1024 &&
              (_png(raw) || _jpg(raw))) {
            cover = Uint8List.fromList(raw);
          }
        } on FormatException {
          // Bad embedded image must not prevent reading the book.
        }
        break;
      }
    }

    final chapters = <String>[];
    for (final body in child(root, 'body')) {
      for (final section in child(body, 'section')) {
        final paragraphs = section
            .descendants
            .whereType<XmlElement>()
            .where((node) => node.name.local == 'p' || node.name.local == 'subtitle')
            .map((node) => node.innerText.trim())
            .where((part) => part.isNotEmpty)
            .toList();
        if (paragraphs.isNotEmpty) chapters.add(paragraphs.join('\n\n'));
      }
    }
    if (chapters.isEmpty) {
      throw const FormatException('Не найден текст глав FB2');
    }
    return ImportedBook(
      title: title?.isNotEmpty == true
          ? title!
          : filename.replaceFirst(RegExp(r'\.[^.]+$'), ''),
      author: authors,
      chapters: chapters,
      cover: cover,
    );
  }

  static bool _png(List<int> bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 &&
      bytes[3] == 71 && bytes[4] == 13 && bytes[5] == 10 &&
      bytes[6] == 26 && bytes[7] == 10;

  static bool _jpg(List<int> bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255;
}
