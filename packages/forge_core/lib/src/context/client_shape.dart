import 'conventions.dart';
import 'scanner.dart';

/// One HTTP verb method on the project's own API client class.
class WrapperMethod {
  const WrapperMethod({this.queryParam, this.bodyParam});

  /// Named argument for query parameters, e.g. `queryParameters`.
  final String? queryParam;

  /// Named argument for the request body, e.g. `data`.
  final String? bodyParam;

  Map<String, Object?> toJson() => {'query': queryParam, 'body': bodyParam};
}

/// How generated repositories should call HTTP, copied from the project.
class ClientShape {
  const ClientShape({
    required this.kind,
    required this.fieldName,
    this.className,
    this.path,
    this.singleton,
    this.methods = const {},
    this.payload = '',
    this.unwrapsEnvelope = false,
  });

  /// `dio`, `http` or `api_client`.
  final String kind;

  /// Field name repositories use for the client, e.g. `_dio`.
  final String fieldName;

  /// For `api_client`: the wrapper class and its file.
  final String? className;
  final String? path;

  /// Static accessor such as `instance`, when the wrapper is a singleton.
  final String? singleton;

  /// Verb (`get`, `post`…) → its arguments.
  final Map<String, WrapperMethod> methods;

  /// Suffix that reads the JSON body from a call's result: `.data` or ``.
  final String payload;

  /// The wrapper's result is already the envelope's `data`.
  final bool unwrapsEnvelope;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'field': fieldName,
    if (className != null) 'class': className,
    if (path != null) 'path': path,
    if (singleton != null) 'singleton': singleton,
    if (methods.isNotEmpty)
      'methods': {for (final e in methods.entries) e.key: e.value.toJson()},
    'payload': payload,
    'unwrapsEnvelope': unwrapsEnvelope,
  };
}

final _fieldRe = RegExp(r'final\s+([\w.]+)\s+(_\w+)\s*;');
final _repoClassRe = RegExp(r'class\s+\w*Repository(Impl)?\b');

/// What the repositories hold, plus the parsed wrapper class (if any).
({Detection kind, Map<String, String> fieldNames}) detectClientKind(
  ScanResult s,
  Detection network,
  Detection apiClient,
) {
  final wrapper = _wrapperClass(s, apiClient.value);
  final counts = <String, List<String>>{};
  final fieldNames = <String, Map<String, int>>{};
  for (final f in s.libFiles) {
    if (!_repoClassRe.hasMatch(f.content)) continue;
    for (final m in _fieldRe.allMatches(f.content)) {
      final type = m.group(1)!;
      final kind = switch (type) {
        'Dio' => 'dio',
        'http.Client' => 'http',
        'Client' when f.importsPackage('http') => 'http',
        _ when type == wrapper => 'api_client',
        _ => null,
      };
      if (kind == null) continue;
      (counts[kind] ??= []).add(f.path);
      final names = fieldNames[kind] ??= {};
      names[m.group(2)!] = (names[m.group(2)!] ?? 0) + 1;
    }
  }
  final preferred = {
    for (final e in fieldNames.entries)
      e.key:
          (e.value.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key,
  };

  if (counts.isNotEmpty) {
    final order = ['api_client', 'dio', 'http'];
    var best = order.firstWhere(counts.containsKey);
    for (final k in order) {
      if ((counts[k]?.length ?? 0) > counts[best]!.length) best = k;
    }
    final total = counts.values.fold<int>(0, (n, l) => n + l.length);
    final files = {...counts[best]!}.toList();
    return (
      kind: Detection(
        best,
        ((0.5 + 0.45 * counts[best]!.length / total) * 100).round() / 100,
        files.take(4).toList(),
      ),
      fieldNames: preferred,
    );
  }
  if (wrapper != null) {
    return (
      kind: Detection('api_client', 0.6, [apiClient.value!]),
      fieldNames: preferred,
    );
  }
  final fallback = switch (network.value) {
    'dio' || 'retrofit' => 'dio',
    'http' => 'http',
    _ => null,
  };
  return (
    kind: fallback == null
        ? const Detection.unknown()
        : Detection(fallback, 0.4, network.evidence),
    fieldNames: preferred,
  );
}

/// The class in [path] that has a `get(String path, …)` method.
String? _wrapperClass(ScanResult s, String? path) {
  if (path == null) return null;
  final file = s.libFiles.where((f) => f.path == path).firstOrNull;
  if (file == null || !_methodRe.hasMatch(file.content)) return null;
  return RegExp(r'class\s+(\w+)').firstMatch(file.content)?.group(1);
}

final _methodRe = RegExp(
  r'Future<(.+?)>\s+(get|post|put|patch|delete)\s*\(\s*String\s+\w+\s*,?\s*(\{[^}]*\})?\s*\)',
);

/// Builds the full shape for [kind]. Returns `null` when [kind] is
/// `api_client` but the wrapper can't be understood.
ClientShape? buildClientShape(
  ScanResult s,
  String kind,
  String? apiClientPath,
  Map<String, String> fieldNames,
) {
  final field =
      fieldNames[kind] ??
      switch (kind) {
        'dio' => '_dio',
        'http' => '_client',
        _ => '_api',
      };
  if (kind != 'api_client') return ClientShape(kind: kind, fieldName: field);

  final className = _wrapperClass(s, apiClientPath);
  if (className == null) return null;
  final file = s.libFiles.firstWhere((f) => f.path == apiClientPath);

  final methods = <String, WrapperMethod>{};
  String? returnType;
  for (final m in _methodRe.allMatches(file.content)) {
    returnType ??= m.group(1)!.trim();
    final named = _splitParams(m.group(3) ?? '');
    String? query;
    String? body;
    for (final (type, name) in named) {
      if (query == null &&
          type.startsWith('Map<String') &&
          name.toLowerCase().contains('query')) {
        query = name;
      }
      if (body == null &&
          const {'data', 'body', 'payload', 'json'}.contains(name)) {
        body = name;
      }
    }
    methods.putIfAbsent(
      m.group(2)!,
      () => WrapperMethod(queryParam: query, bodyParam: body),
    );
  }

  final singleton = RegExp(
    r'static\s+(?:final\s+|const\s+)?(?:\w+\s+)?(?:get\s+)?(instance|shared|i)\b',
  ).firstMatch(file.content)?.group(1);

  var payload = '';
  var unwraps = false;
  final rt = returnType ?? 'dynamic';
  if (rt.startsWith('Response')) {
    payload = '.data';
  } else if (!const {
    'dynamic',
    'Object?',
    'Object',
    'Map<String, dynamic>',
    'Map<String, dynamic>?',
  }.contains(rt)) {
    // A result class: if it has a `data` field it is the unwrapped envelope.
    final hasData = s.libFiles.any(
      (f) =>
          RegExp('class\\s+$rt\\b').hasMatch(f.content) &&
          RegExp(r'final\s+[\w<>?, ]+\s+data\s*;').hasMatch(f.content),
    );
    if (hasData) {
      payload = '.data';
      unwraps = true;
    }
  }

  return ClientShape(
    kind: kind,
    fieldName: field,
    className: className,
    path: apiClientPath,
    singleton: singleton,
    methods: methods,
    payload: payload,
    unwrapsEnvelope: unwraps,
  );
}

/// `{required Map<String, dynamic>? q, Object? data = x}` → [(type, name)].
List<(String, String)> _splitParams(String braces) {
  final inner = braces.replaceAll(RegExp(r'^\{|\}$'), '');
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < inner.length; i++) {
    final c = inner[i];
    if (c == '<' || c == '(') depth++;
    if (c == '>' || c == ')') depth--;
    if (c == ',' && depth == 0) {
      parts.add(inner.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(inner.substring(start));
  final out = <(String, String)>[];
  for (final raw in parts) {
    final part = raw.split('=').first.replaceAll('required ', '').trim();
    final cut = part.lastIndexOf(RegExp(r'\s'));
    if (cut <= 0) continue;
    out.add((part.substring(0, cut).trim(), part.substring(cut + 1)));
  }
  return out;
}

/// `package` or `relative`, by how lib files import each other.
Detection detectImportStyle(ScanResult s, String packageName) {
  final pkg = <String>[];
  final rel = <String>[];
  for (final f in s.libFiles) {
    for (final uri in f.imports) {
      if (uri.startsWith('package:$packageName/')) {
        pkg.add(f.path);
      } else if (!uri.contains(':')) {
        rel.add(f.path);
      }
    }
  }
  final total = pkg.length + rel.length;
  if (total == 0) return const Detection.unknown();
  final usePkg = pkg.length >= rel.length;
  final files = {...(usePkg ? pkg : rel)}.take(4).toList();
  return Detection(
    usePkg ? 'package' : 'relative',
    ((0.5 + 0.45 * (usePkg ? pkg.length : rel.length) / total) * 100).round() /
        100,
    files,
  );
}
