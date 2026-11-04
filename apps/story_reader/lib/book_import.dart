import 'dart:convert';
import 'dart:typed_data';
import 'package:xml/xml.dart';
import 'package:archive/archive.dart';
import 'book_model.dart';
import 'book_text_decoder.dart';

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
  // Some FB2 editions place a numbered sequence inside ONE <section>,
  // encoding each part heading as a plain <p>. Preserve the book as a
  // single file, but use validated sequential parts as reading chapters.
  // No speculative split based on capitalization or a single stray phrase.
  static final RegExp _numberedPartHeading = RegExp(
    r'^(?:рассказ|история)\s+'
    r'(первый|второй|третий|четвёртый|четвертый|пятый|'
    r'шестой|седьмой|восьмой|девятый|десятый)'
    r'(?:$|[\s,.:;—-])',
    caseSensitive: false,
    unicode: true,
  );
  static const _partNumbers = <String, int>{
    'первый': 1, 'второй': 2, 'третий': 3,
    'четвертый': 4, 'пятый': 5, 'шестой': 6,
    'седьмой': 7, 'восьмой': 8, 'девятый': 9,
    'десятый': 10,
  };

  /// Public display label for a numbered story heading stored as an FB2
  /// paragraph (not necessarily as <title>). The importer remains the source
  /// of truth; the reader must not invent its own different numbering regex.
  static String? numberedStoryPartLabel(BookBlock block) {
    if (block.kind != BookBlockKind.paragraph &&
        block.kind != BookBlockKind.heading) return null;
    final text = block.text.trim();
    final match = _numberedPartHeading.firstMatch(text);
    if (match == null) return null;
    final firstWord = text.split(RegExp(r'\s+')).first;
    return '$firstWord ${match.group(1)}';
  }

  static int? _numberedPart(BookBlock block) {
    if (block.kind != BookBlockKind.paragraph &&
        block.kind != BookBlockKind.heading) return null;
    final match = _numberedPartHeading.firstMatch(block.text.trim());
    if (match == null) return null;
    return _partNumbers[match.group(1)!.toLowerCase().replaceAll('ё', 'е')];
  }

  static List<List<BookBlock>> _splitNumberedStoryParts(
      List<BookBlock> blocks) {
    final markers = <(int, int)>[];
    for (var i = 0; i < blocks.length; i++) {
      final number = _numberedPart(blocks[i]);
      if (number != null) markers.add((i, number));
    }
    // Need at least three sequential explicit headings beginning with the
    // first. Otherwise an isolated phrase must not silently alter offsets.
    if (markers.length < 3 || markers.first.$2 != 1) return [blocks];
    for (var i = 0; i < markers.length; i++) {
      if (markers[i].$2 != i + 1) return [blocks];
    }
    final parts = <List<BookBlock>>[];
    for (var i = 0; i < markers.length; i++) {
      final start = i == 0 ? 0 : markers[i].$1;
      final end = i + 1 == markers.length
          ? blocks.length : markers[i + 1].$1;
      parts.add(blocks.sublist(start, end));
    }
    return parts;
  }

  static ImportedBook parse(String filename, Uint8List bytes) {
    if (bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('Максимальный размер книги — 20 МБ');
    }
    final ext = filename.split('.').last.toLowerCase();
    if (ext == 'zip') return _fb2Zip(bytes);
    if (ext != 'txt' && ext != 'fb2') {
      throw const FormatException('Поддерживаются TXT, FB2 и FB2.ZIP');
    }
    final text = BookTextDecoder.decode(filename, bytes);
    if (ext == 'txt') {
      // Preserve all user-authored whitespace for exact TXT source ranges.
      // Strip only the UTF-8 BOM, which is an encoding marker, not content.
      final body = text.startsWith('\ufeff') ? text.substring(1) : text;
      if (body.trim().isEmpty) throw const FormatException('Файл пуст');
      return ImportedBook(
        title: filename.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        author: '',
        chapters: [body],
      );
    }
    return _fb2(text, filename);
  }

  /// A reader can import a user-owned .fb2.zip without sharing its bytes
  /// or extracting any files on disk. A ZIP must contain exactly one FB2.
  /// Inspect central-directory sizes BEFORE CRC-verifying/decompressing.
  static ImportedBook _fb2Zip(Uint8List bytes) {
    const maxBytes = 20 * 1024 * 1024;
    try {
      final header = ZipDecoder().decodeBytes(bytes);
      if (header.files.isEmpty || header.files.length > 24) {
        throw const FormatException('В ZIP слишком много файлов.');
      }
      final files = header.files.where((file) => file.isFile).toList();
      if (files.length != 1) {
        throw const FormatException(
            'Архив должен содержать ровно один файл FB2.');
      }
      final item = files.single;
      final segments = item.name.split('/');
      if (item.name.startsWith('/') ||
          item.name.contains('\\') ||
          segments.any((segment) =>
              segment.isEmpty || segment == '.' || segment == '..') ||
          !item.name.toLowerCase().endsWith('.fb2')) {
        throw const FormatException(
            'В архиве нет единственной безопасной книги FB2.');
      }
      if (item.size == 0 || item.size > maxBytes) {
        throw const FormatException(
            'Распакованная книга должна быть не больше 20 МБ.');
      }
      // The single bounded FB2 is the ONLY file body decoded. CRC errors,
      // malformed ZIPs and password-protected archives are not accepted.
      final verified = ZipDecoder().decodeBytes(bytes, verify: true);
      final safe = verified.files.where((file) => file.isFile).single;
      final content = safe.readBytes();
      if (content == null || content.length != item.size) {
        throw const FormatException('Размер книги в ZIP не совпал.');
      }
      return parse(segments.last, content);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
          'Не удалось проверить ZIP. Выберите архив с одним файлом FB2.');
    }
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
        final encoded = binary.innerText.replaceAll(RegExp(r'\s'), '');
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
      if (name == 'title') {
        final heading = node.innerText.trim();
        if (heading.isNotEmpty) {
          blocks.add(BookBlock(kind: BookBlockKind.heading, text: heading));
        }
        return;
      }
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
            buffer.write(part is XmlText ? part.value : part.innerText);
          }
        }
        flush();
        return;
      }
      for (final element in node.children.whereType<XmlElement>()) {
        appendNode(element, blocks);
      }
    }

    // FB2 often stores numbered footnotes in a separate <body name="notes">.
    // Its <section> elements are NOT extra story chapters. Preserve all note
    // text in one clearly labeled appendix while keeping the main tales as
    // separate chapters. Other named bodies retain their original behavior.
    final auxiliaryBodies = <XmlElement>[];
    for (final body in child(root, 'body')) {
      final role = (body.getAttribute('name') ?? '').trim().toLowerCase();
      if (role == 'notes' || role == 'comments') {
        auxiliaryBodies.add(body);
        continue;
      }
      final sections = child(body, 'section').toList();
      if (sections.isEmpty) {
        final blocks = <BookBlock>[];
        appendNode(body, blocks);
        if (blocks.isNotEmpty) {
          structured.add(BookChapter(
            id: 'chapter_${structured.length}', blocks: blocks,
          ));
        }
      } else {
        for (final section in sections) {
          final blocks = <BookBlock>[];
          appendNode(section, blocks);
          if (blocks.isNotEmpty) {
            for (final part in _splitNumberedStoryParts(blocks)) {
              structured.add(BookChapter(
                id: 'chapter_${structured.length}', blocks: part,
              ));
            }
          }
        }
      }
    }
    for (final body in auxiliaryBodies) {
      final role = (body.getAttribute('name') ?? '').trim().toLowerCase();
      final blocks = <BookBlock>[
        BookBlock(
          kind: BookBlockKind.heading,
          text: role == 'notes' ? 'Примечания' : 'Комментарии',
        ),
      ];
      // Keep numbered note titles and their complete contents in source
      // order, without presenting each note as an independent fairy tale.
      appendNode(body, blocks);
      if (blocks.length > 1) {
        structured.add(BookChapter(
          id: 'chapter_${structured.length}', blocks: blocks,
        ));
      }
    }
    for (final chapter in structured) {
      chapters.add(chapter.blocks
          .where((block) => block.kind != BookBlockKind.image)
          .map((block) => block.text)
          .join('\n\n'));
    }
    if (structured.isEmpty) {
      throw const FormatException('Не найдены главы FB2');
    }
    return ImportedBook(
      title: title?.isNotEmpty == true
          ? title!
          : filename.replaceFirst(RegExp(r'\.[^.]+$'), ''),
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
