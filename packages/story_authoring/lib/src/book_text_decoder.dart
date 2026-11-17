import 'dart:convert';
import 'dart:typed_data';

/// Decode plain-text book formats without trusting the XML encoding label
/// blindly. UTF-8, Windows-1251 (common Russian FB2/TXT) and BOM-marked
/// UTF-16 are supported. Unknown encodings fail clearly, not as garbled text.
class BookTextDecoder {
  const BookTextDecoder._();

  static const _cp1251Symbols = <int>[
    0x0402, 0x0403, 0x201a, 0x0453, 0x201e, 0x2026, 0x2020, 0x2021,
    0x20ac, 0x2030, 0x0409, 0x2039, 0x040a, 0x040c, 0x040b, 0x040f,
    0x0452, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
    0xfffd, 0x2122, 0x0459, 0x203a, 0x045a, 0x045c, 0x045b, 0x045f,
    0x00a0, 0x040e, 0x045e, 0x0408, 0x00a4, 0x0490, 0x00a6, 0x00a7,
    0x0401, 0x00a9, 0x0404, 0x00ab, 0x00ac, 0x00ad, 0x00ae, 0x0407,
    0x00b0, 0x00b1, 0x0406, 0x0456, 0x0491, 0x00b5, 0x00b6, 0x00b7,
    0x0451, 0x2116, 0x0454, 0x00bb, 0x0458, 0x0405, 0x0455, 0x0457,
  ];

  static String _cp1251(Uint8List bytes) {
    final runes = <int>[];
    for (final byte in bytes) {
      if (byte < 0x80) {
        runes.add(byte);
      } else if (byte < 0xc0) {
        final code = _cp1251Symbols[byte - 0x80];
        if (code == 0xfffd) {
          throw const FormatException('Повреждённая кодировка Windows-1251');
        }
        runes.add(code);
      } else {
        runes.add(byte < 0xe0
            ? byte - 0xc0 + 0x0410
            : byte - 0xe0 + 0x0430);
      }
    }
    return String.fromCharCodes(runes);
  }

  static String _utf16(Uint8List bytes, {required bool littleEndian}) {
    if ((bytes.length - 2).isOdd) {
      throw const FormatException('Неполные байты UTF-16 в книге');
    }
    final units = <int>[];
    for (var i = 2; i < bytes.length; i += 2) {
      units.add(littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1]);
    }
    // Reject invalid surrogate pairs rather than silently replacing text.
    for (var i = 0; i < units.length; i++) {
      final c = units[i];
      if (c >= 0xd800 && c <= 0xdbff) {
        if (++i >= units.length ||
            units[i] < 0xdc00 || units[i] > 0xdfff) {
          throw const FormatException('Повреждён символ UTF-16');
        }
      } else if (c >= 0xdc00 && c <= 0xdfff) {
        throw const FormatException('Повреждён символ UTF-16');
      }
    }
    return String.fromCharCodes(units);
  }

  static String decode(String filename, Uint8List bytes) {
    if (bytes.isEmpty) return '';
    if (bytes.length >= 2 &&
        bytes[0] == 0xff && bytes[1] == 0xfe) {
      return _utf16(bytes, littleEndian: true);
    }
    if (bytes.length >= 2 &&
        bytes[0] == 0xfe && bytes[1] == 0xff) {
      return _utf16(bytes, littleEndian: false);
    }
    final isFb2 = filename.toLowerCase().endsWith('.fb2');
    final prefix = latin1.decode(bytes.take(256).toList());
    final declaration = isFb2
        ? RegExp(r'''encoding\s*=\s*["']([^"']+)["']''',
            caseSensitive: false).firstMatch(prefix)
        : null;
    final specifiedEncoding = declaration?.group(1)?.toLowerCase()
        .replaceAll('_', '-');
    if (specifiedEncoding == 'windows-1251' ||
        specifiedEncoding == 'cp1251' ||
        specifiedEncoding == 'windows1251') {
      return _cp1251(bytes);
    }
    if (specifiedEncoding != null &&
        specifiedEncoding != 'utf-8' &&
        specifiedEncoding != 'utf8') {
      throw FormatException('Кодировка $specifiedEncoding не поддерживается. '
          'Сохраните книгу в UTF-8, Windows-1251 или UTF-16 с BOM.');
    }
    try {
      final text = utf8.decode(bytes, allowMalformed: false);
      return text.startsWith('\ufeff') ? text.substring(1) : text;
    } on FormatException {
      if (specifiedEncoding != null) {
        throw const FormatException(
            'Текст не соответствует заявленной кодировке UTF-8');
      }
      // Text-only fallback for common old Russian TXT and FB2 without a
      // declaration. Reject unreadable binary instead of showing mojibake.
      final text = _cp1251(bytes);
      final cyrillic = RegExp(r'[А-Яа-яЁё]').allMatches(text).length;
      if (cyrillic < 3 || text.contains('\u0000')) {
        throw const FormatException('Не удалось распознать кодировку. '
            'Поддерживаются UTF-8 и Windows-1251.');
      }
      return text;
    }
  }
}
