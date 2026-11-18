import 'package:yaml/yaml.dart';

import '../context/project_context.dart';

/// `.flutter_dialect.yaml`: explicit conventions that beat detection.
class DialectConfig {
  const DialectConfig({this.conventions = const {}, this.paths = const {}});

  static const fileName = '.flutter_dialect.yaml';

  /// Allowed values per convention key.
  static const allowedConventions = <String, List<String>>{
    'layout': ['flat-feature', 'layered-feature', 'layer-first'],
    'state': ['set-state', 'provider', 'riverpod', 'bloc', 'getx'],
    'router': ['go_router', 'auto_route', 'navigator'],
    'network': ['dio', 'http', 'chopper', 'retrofit'],
    'di': ['get_it', 'injectable', 'provider', 'riverpod', 'constructor'],
    'models': ['freezed', 'json_serializable', 'hand-written'],
    'repository': ['concrete', 'interface+impl'],
    'json_methods': ['fromJson/toJson', 'fromMap/toMap'],
    'client': ['dio', 'http', 'api_client'],
    'imports': ['package', 'relative'],
  };

  static const allowedPaths = ['features', 'api_client'];

  final Map<String, String> conventions;
  final Map<String, String> paths;

  /// Parses and validates config text. Throws [FormatException].
  factory DialectConfig.parse(String text) {
    final Object? doc;
    try {
      doc = loadYaml(text);
    } on YamlException catch (e) {
      throw FormatException('$fileName: ${e.message}');
    }
    if (doc == null) return const DialectConfig();
    if (doc is! YamlMap) throw FormatException('$fileName: expected a map');

    for (final key in doc.keys) {
      if (!const ['version', 'conventions', 'paths'].contains(key)) {
        throw FormatException('$fileName: unknown key "$key"');
      }
    }
    final version = doc['version'] ?? 1;
    if (version != 1) {
      throw FormatException('$fileName: unsupported version $version');
    }

    final conventions = _stringMap(doc['conventions'], 'conventions');
    conventions.forEach((key, value) {
      final allowed = allowedConventions[key];
      if (allowed == null) {
        throw FormatException(
          '$fileName: unknown convention "$key" '
          '(allowed: ${allowedConventions.keys.join(', ')})',
        );
      }
      if (!allowed.contains(value)) {
        throw FormatException(
          '$fileName: invalid $key "$value" (allowed: ${allowed.join(', ')})',
        );
      }
    });

    final paths = _stringMap(doc['paths'], 'paths');
    for (final key in paths.keys) {
      if (!allowedPaths.contains(key)) {
        throw FormatException('$fileName: unknown path "$key"');
      }
    }
    return DialectConfig(conventions: conventions, paths: paths);
  }

  /// A config pinning everything that was detected.
  factory DialectConfig.fromContext(ProjectContext ctx) {
    final conventions = <String, String>{};
    ctx.conventions.forEach((key, d) {
      if (d.value != null) conventions[key] = d.value!;
    });
    return DialectConfig(
      conventions: conventions,
      paths: {
        if (ctx.featuresPath != null) 'features': ctx.featuresPath!,
        if (ctx.apiClient.value != null) 'api_client': ctx.apiClient.value!,
      },
    );
  }

  String toYaml() {
    final b = StringBuffer()
      ..writeln(
        '# Flutter Dialect conventions. Values here override detection.',
      )
      ..writeln('# Run `flutter_dialect context` to see what was detected.')
      ..writeln('version: 1');
    if (conventions.isNotEmpty) {
      b.writeln('conventions:');
      for (final key in allowedConventions.keys) {
        final v = conventions[key];
        if (v != null) b.writeln('  $key: $v');
      }
    }
    if (paths.isNotEmpty) {
      b.writeln('paths:');
      for (final key in allowedPaths) {
        final v = paths[key];
        if (v != null) b.writeln('  $key: $v');
      }
    }
    return b.toString();
  }

  static Map<String, String> _stringMap(Object? node, String name) {
    if (node == null) return {};
    if (node is! YamlMap) {
      throw FormatException('$fileName: "$name" must be a map');
    }
    return {
      for (final e in node.entries)
        '${e.key}': switch (e.value) {
          final String s => s,
          _ => throw FormatException(
            '$fileName: $name.${e.key} must be a string',
          ),
        },
    };
  }
}
