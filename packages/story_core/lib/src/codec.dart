import 'dart:collection';
import 'dart:convert';

/// Stable JSON representation. Objects have sorted keys, lists keep order.
/// Never hash the source JSON string (whitespace/key order are irrelevant).
String canonicalJson(Object? value) => jsonEncode(_sort(value));

Object? _sort(Object? value) {
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) {
      throw const FormatException('JSON object keys must be strings');
    }
    final result = SplayTreeMap<String, Object?>();
    for (final key in value.keys.cast<String>()) {
      result[key] = _sort(value[key]);
    }
    return result;
  }
  if (value is List) return value.map(_sort).toList(growable: false);
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  throw const FormatException('Unsupported non-integer JSON value');
}

Map<String, dynamic> jsonObject(Object? raw, String field) {
  if (raw is! Map<String, dynamic>) {
    throw FormatException('$field must be an object');
  }
  return raw;
}

List<dynamic> jsonArray(Object? raw, String field) {
  if (raw is! List) throw FormatException('$field must be an array');
  return raw;
}

String jsonId(Object? raw, String field) {
  if (raw is! String ||
      !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(raw)) {
    throw FormatException('$field: invalid identifier');
  }
  return raw;
}

void assertFields(
  Map<String, dynamic> raw,
  String field,
  Set<String> required,
  Set<String> allowed,
) {
  if (!raw.keys.toSet().containsAll(required) ||
      raw.keys.any((key) => !allowed.contains(key))) {
    throw FormatException('$field: unsupported or missing keys');
  }
}
