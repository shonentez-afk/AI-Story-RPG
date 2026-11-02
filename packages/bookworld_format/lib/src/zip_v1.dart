import 'dart:convert';
import 'dart:typed_data';

/// Deliberately small, read-only ZIP subset for .bworld v1.
///
/// Only exact, uncompressed, non-encrypted, non-Zip64 entries are allowed.
/// Rejects ambiguous ZIP tricks: duplicate names, paths, symlinks, metadata
/// descriptors, extra fields, multiple central directories and trailing data.
/// No entry is ever extracted to a caller-specified filesystem path.
class BworldZipV1 {
  BworldZipV1._();

  static const int maxArchive = 12 * 1024 * 1024;
  static const int maxEntry = 8 * 1024 * 1024;
  static const int maxTotal = 16 * 1024 * 1024;
  static const List<String> paths = [
    'manifest.json', 'scenario/blueprint.json', 'world.sqlite',
  ];

  /// Exact v2 private archive entries. V1 read() is unchanged and rejects
  /// v2 archives; the caller must explicitly opt into this format.
  static const List<String> privatePaths = [
    'manifest.json', 'scenario/blueprint.json',
    'source/provenance.json', 'world.sqlite',
  ];

  static Map<String, Uint8List> read(Uint8List bytes) =>
      _readExpected(bytes, paths);

  static Map<String, Uint8List> readPrivate(Uint8List bytes) =>
      _readExpected(bytes, privatePaths);

  static Map<String, Uint8List> _readExpected(
      Uint8List bytes, List<String> paths) {
    if (bytes.length < 22 || bytes.length > maxArchive) {
      throw const FormatException('Invalid .bworld archive size');
    }
    final binary = ByteData.sublistView(bytes);
    final len = bytes.length;
    int u16(int offset) {
      if (offset < 0 || offset + 2 > len) {
        throw const FormatException('ZIP truncated');
      }
      return binary.getUint16(offset, Endian.little);
    }

    int u32(int offset) {
      if (offset < 0 || offset + 4 > len) {
        throw const FormatException('ZIP truncated');
      }
      return binary.getUint32(offset, Endian.little);
    }

    final tail = len - 22;
    if (u32(tail) != 0x06054b50 ||
        u16(tail + 4) != 0 || u16(tail + 6) != 0 ||
        u16(tail + 8) != paths.length ||
        u16(tail + 10) != paths.length ||
        u16(tail + 20) != 0) {
      throw const FormatException('ZIP end record not supported');
    }
    final centralSize = u32(tail + 12);
    final centralOffset = u32(tail + 16);
    if (centralOffset + centralSize != tail ||
        centralOffset >= len || centralSize < paths.length * 46) {
      throw const FormatException('Invalid ZIP central directory');
    }
    var cursor = centralOffset;
    var localCursor = 0;
    var totalSize = 0;
    final result = <String, Uint8List>{};
    for (final expectedName in paths) {
      if (cursor + 46 > tail || u32(cursor) != 0x02014b50) {
        throw const FormatException('Missing ZIP central entry');
      }
      final flag = u16(cursor + 8);
      final method = u16(cursor + 10);
      final crc = u32(cursor + 16);
      final stored = u32(cursor + 20);
      final expanded = u32(cursor + 24);
      final nameLength = u16(cursor + 28);
      final extra = u16(cursor + 30);
      final comment = u16(cursor + 32);
      final disk = u16(cursor + 34);
      final external = u32(cursor + 38);
      final offset = u32(cursor + 42);
      final next = cursor + 46 + nameLength + extra + comment;
      if (flag != 0 || method != 0 || extra != 0 || comment != 0 ||
          disk != 0 || stored != expanded || expanded > maxEntry ||
          next > tail || nameLength == 0 || offset != localCursor ||
          ((external >>> 16) & 0xf000) == 0xa000) {
        throw const FormatException('Unsupported/unsafe ZIP entry');
      }
      final name = ascii.decode(bytes.sublist(cursor + 46,
          cursor + 46 + nameLength), allowInvalid: false);
      if (name != expectedName || result.containsKey(name)) {
        throw const FormatException('Unexpected or duplicate ZIP path');
      }
      cursor = next;
      if (localCursor + 30 > centralOffset ||
          u32(localCursor) != 0x04034b50 ||
          u16(localCursor + 6) != flag ||
          u16(localCursor + 8) != method ||
          u32(localCursor + 14) != crc ||
          u32(localCursor + 18) != stored ||
          u32(localCursor + 22) != expanded ||
          u16(localCursor + 26) != nameLength ||
          u16(localCursor + 28) != 0) {
        throw const FormatException('ZIP local/central header mismatch');
      }
      final localName = ascii.decode(
        bytes.sublist(localCursor + 30, localCursor + 30 + nameLength),
        allowInvalid: false,
      );
      if (localName != name) {
        throw const FormatException('ZIP local path mismatch');
      }
      final dataStart = localCursor + 30 + nameLength;
      final dataEnd = dataStart + stored;
      if (dataEnd > centralOffset) {
        throw const FormatException('ZIP data extends beyond local area');
      }
      final entryBytes = Uint8List.sublistView(bytes, dataStart, dataEnd);
      if (_crc32(entryBytes) != crc) {
        throw const FormatException('ZIP CRC32 mismatch');
      }
      result[name] = entryBytes;
      localCursor = dataEnd;
      totalSize += expanded;
    }
    if (cursor != tail || localCursor != centralOffset ||
        totalSize > maxTotal) {
      throw const FormatException('Unexpected ZIP payload/central records');
    }
    return Map.unmodifiable(result);
  }

  static final List<int> _crcTable = List.generate(256, (n) {
    var value = n;
    for (var i = 0; i < 8; ++i) {
      value = value & 1 != 0
          ? 0xedb88320 ^ (value >>> 1)
          : value >>> 1;
    }
    return value;
  });

  static int _crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final value in bytes) {
      crc = _crcTable[(crc ^ value) & 0xff] ^ (crc >>> 8);
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }
}
