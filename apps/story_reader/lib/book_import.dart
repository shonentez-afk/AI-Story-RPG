import 'dart:convert';
import 'dart:typed_data';
import 'package:xml/xml.dart';
import 'book_model.dart';

class ImportedBook {
  const ImportedBook({
    required this.title,
    required this.author,
    required this.chapters,
    this.cover,
    this.structuredChapters = const [],
    this.images = const {},
  });

  final String title;
  final String author;
  final List<String> chapters;
  final Uint8List? cover;
  final List<BookChapter> structuredChapters;
  final Map<String, BookImage> images;

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

    final resources = <String, BookImage>{};
    for (final binary in child(root, 'binary')) {
      final imageId = binary.getAttribute('id');
      if (imageId == null || imageId.isEmpty) continue;
      try {
        final encoded = binary.innerText.replaceAll(RegExp(r'\\s'), '');
        if (encoded.length > 12 * 1024 * 1024) continue;
        final decoded = base64.decode(encoded);
        if (decoded.isEmpty || decoded.length > 8 * 1024 * 1024) continue;
        final type = _png(decoded) ? 'image/png' : _jpg(decoded) ? 'image/jpeg' : null;
        if (type != null) {
          resources[imageId] = BookImage(
            id: imageId, bytes: Uint8List.fromList(decoded), mediaType: type,
          );
        }
      } on FormatException {
        // Unreadable images should not discard an otherwise readable book.
      }
    }

    String? imageIdFrom(XmlElement? element) {
      if (element == null) return null;
      for (final attr in element.attributes) {
        if (attr.name.local == 'href' && attr.value.startsWith('#')) {
          return attr.value.substring(1);
        }
      }
      return null;
    }

    final coverId = imageIdFrom(first(first(titleInfo, 'coverpage'), 'image'));
    final cover = resources[coverId]?.bytes;
    final chapters = <String>[];
    final structured = <BookChapter>[];

    // Preserve document order, including nested sections and inline images.
    void appendNode(XmlElement node, List<BookBlock> blocks) {
      final name = node.name.local;
      if (name == 'image') {
        final ref = imageIdFrom(node);
        if (ref != null) {
          blocks.add(BookBlock(kind: BookBlockKind.image, resourceId: ref));
        }
        return;
      }
      if (name == 'p' || name == 'subtitle' || name == 'v') {
        // Inline image within a paragraph must keep its original position.
        final buffer = StringBuffer();
        void flush() {
          final value = buffer.toString().trim();
          if (value.isNotEmpty) {
            blocks.add(BookBlock(
              kind: name == 'subtitle' ? BookBlockKind.heading : BookBlockKind.paragraph,
              text: value,
            ));
          }
          buffer.clear();
        }
        for (final part in node.children) {
          if (part is XmlElement && part.name.local == 'image') {
            flush();
            appendNode(part, blocks);
          } else {
            buffer.write(part is XmlElement ? part.innerText : part.value);
          }
        }
        flush();
        return;
      }
      for (final element in node.children.whereType<XmlElement>()) {
        appendNode(element, blocks);
      }
    }

    for (final body in child(root, 'body')) {
      final sections = child(body, 'section').toList();
      if (sections.isEmpty) {
        final blocks = <BookBlock>[];
        appendNode(body, blocks);
        if (blocks.isNotEmpty) {
          structured.add(BookChapter(id: 'chapter_${structured.length}', blocks: blocks));
        }
      } else {
        for (final section in sections) {
          final blocks = <BookBlock>[];
          appendNode(section, blocks);
          if (blocks.isNotEmpty) {
            structured.add(BookChapter(id: 'chapter_${structured.length}', blocks: blocks));
          }
        }
      }
    }
    for (final chapter in structured) {
      chapters.add(chapter.blocks
          .where((block) => block.kind != BookBlockKind.image)
          .map((block) => block.text)
          .join('\\n\\n'));
    }
    if (structured.isEmpty) {
      throw const FormatException('Не найдены главы FB2');
    }
    return ImportedBook(
      title: title?.isNotEmpty == true
          ? title!
          : filename.replaceFirst(RegExp(r'\\.[^.]+$'), ''),
      author: authors,
      chapters: chapters,
      structuredChapters: structured,
      images: resources,
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
