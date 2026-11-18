/// Turning arbitrary API names into Dart identifiers.
library;

final _boundary = RegExp(r'(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])');
final _separator = RegExp(r'[^A-Za-z0-9]+');

/// `parent_id` → [parent, id]; `HTTPServer` → [HTTP, Server].
List<String> words(String s) => [
  for (final chunk in s.split(_separator))
    for (final w in chunk.split(_boundary))
      if (w.isNotEmpty) w,
];

String _cap(String w) => w[0].toUpperCase() + w.substring(1).toLowerCase();

String pascal(String s) => words(s).map(_cap).join();

String camel(String s) {
  final p = pascal(s);
  return p.isEmpty ? p : p[0].toLowerCase() + p.substring(1);
}

String snake(String s) => words(s).map((w) => w.toLowerCase()).join('_');

const _reserved = {
  'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch', //
  'class', 'const', 'continue', 'covariant', 'default', 'deferred', 'do',
  'dynamic', 'else', 'enum', 'export', 'extends', 'extension', 'external',
  'factory', 'false', 'final', 'finally', 'for', 'Function', 'if',
  'implements', 'import', 'in', 'interface', 'is', 'late', 'library',
  'mixin', 'new', 'null', 'operator', 'part', 'required', 'rethrow',
  'return', 'static', 'super', 'switch', 'this', 'throw', 'true', 'try',
  'typedef', 'var', 'void', 'while', 'with', 'yield',
  // Object members a field must not shadow.
  'hashCode', 'runtimeType', 'toString', 'noSuchMethod',
};

const _enumReserved = {'values', 'index', 'name'};

/// A legal lowerCamel identifier for a field, parameter or enum value.
String identifier(String s, {bool isEnumValue = false}) {
  var id = camel(s);
  if (id.isEmpty) return 'value';
  if (RegExp(r'^[0-9]').hasMatch(id)) id = 'v$id';
  if (_reserved.contains(id) || (isEnumValue && _enumReserved.contains(id))) {
    id = '${id}Value';
  }
  return id;
}

/// dart:core types a generated class must not be named after.
const coreTypeNames = {
  'BigInt', 'Comparable', 'DateTime', 'Duration', 'Enum', 'Error', //
  'Exception', 'Function', 'Future', 'Invocation', 'Iterable', 'Iterator',
  'List', 'Map', 'Match', 'Null', 'Object', 'Pattern', 'Record', 'RegExp',
  'Set', 'Sink', 'Stream', 'String', 'StringBuffer', 'Symbol', 'Type', 'Uri',
};
