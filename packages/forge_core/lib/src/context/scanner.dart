import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Thrown when a directory can't be scanned as a Dart/Flutter project.
class ScanException implements Exception {
  ScanException(this.message);
  final String message;
  @override
  String toString() => 'ScanException: $message';
}

/// A Dart source file, path relative to the project root (always `/`).
class SourceFile {
  SourceFile(this.path, this.content) : imports = _parseImports(content);

  final String path;
  final String content;

  /// `import`/`export` URIs, in source order.
  final List<String> imports;

  String get basename => p.posix.basenameWithoutExtension(path);

  bool importsPackage(String package) =>
      imports.any((uri) => uri.startsWith('package:$package/'));

  static final _importRe = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );

  static List<String> _parseImports(String content) => [
    for (final m in _importRe.allMatches(content)) m.group(1)!,
  ];
}

/// Raw facts read from a project. No interpretation happens here.
class ScanResult {
  ScanResult({
    required this.root,
    required this.pubspec,
    required this.dependencies,
    required this.devDependencies,
    required this.libFiles,
    required this.testFiles,
    required this.libDirs,
    required this.rootEntries,
    required this.configYaml,
  });

  final String root;
  final Map<String, Object?> pubspec;
  final Set<String> dependencies;
  final Set<String> devDependencies;

  /// Non-generated `.dart` files under `lib/`, sorted by path.
  final List<SourceFile> libFiles;

  /// `.dart` files under `test/`, sorted by path.
  final List<SourceFile> testFiles;

  /// Every directory under `lib/` (relative, sorted), generated dirs excluded.
  final List<String> libDirs;

  /// Names of the entries directly inside the project root.
  final Set<String> rootEntries;

  /// Contents of `.flutterforge.yaml`, if present.
  final String? configYaml;

  bool hasDependency(String name) =>
      dependencies.contains(name) || devDependencies.contains(name);
}

/// Reads a project directory from disk.
class ProjectScanner {
  static const _generatedSuffixes = [
    '.g.dart',
    '.freezed.dart',
    '.gr.dart',
    '.config.dart',
    '.mocks.dart',
    '.pb.dart',
    '.pbenum.dart',
    '.pbjson.dart',
    '.pbserver.dart',
  ];
  static const _generatedDirs = {'gen', 'generated', '.dart_tool', 'build'};

  ScanResult scan(String root) {
    final rootDir = Directory(root);
    final pubspecFile = File(p.join(root, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw ScanException('No pubspec.yaml found in $root');
    }
    final Map<String, Object?> pubspec;
    try {
      final doc = loadYaml(pubspecFile.readAsStringSync());
      pubspec = doc is YamlMap ? _plain(doc) as Map<String, Object?> : {};
    } on YamlException catch (e) {
      throw ScanException('Invalid pubspec.yaml: ${e.message}');
    }

    final configFile = File(p.join(root, '.flutterforge.yaml'));

    final libDirs = <String>[];
    final libFiles = _dartFiles(root, 'lib', libDirs);
    final testFiles = _dartFiles(root, 'test', null);

    return ScanResult(
      root: p.normalize(p.absolute(root)),
      pubspec: pubspec,
      dependencies: _keys(pubspec['dependencies']),
      devDependencies: _keys(pubspec['dev_dependencies']),
      libFiles: libFiles,
      testFiles: testFiles,
      libDirs: libDirs..sort(),
      rootEntries: {
        for (final e in rootDir.listSync(followLinks: false))
          p.basename(e.path),
      },
      configYaml: configFile.existsSync()
          ? configFile.readAsStringSync()
          : null,
    );
  }

  List<SourceFile> _dartFiles(String root, String sub, List<String>? dirsOut) {
    final dir = Directory(p.join(root, sub));
    if (!dir.existsSync()) return [];
    final files = <SourceFile>[];
    void walk(Directory d) {
      final entries = d.listSync(followLinks: false)
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final e in entries) {
        final name = p.basename(e.path);
        if (e is Directory) {
          if (_generatedDirs.contains(name) || name.startsWith('.')) continue;
          dirsOut?.add(_rel(root, e.path));
          walk(e);
        } else if (e is File &&
            name.endsWith('.dart') &&
            !_generatedSuffixes.any(name.endsWith)) {
          files.add(SourceFile(_rel(root, e.path), e.readAsStringSync()));
        }
      }
    }

    walk(dir);
    return files;
  }

  static String _rel(String root, String path) =>
      p.split(p.relative(path, from: root)).join('/');

  static Set<String> _keys(Object? section) =>
      section is Map ? {for (final k in section.keys) '$k'} : {};

  static Object? _plain(Object? node) => switch (node) {
    YamlMap m => {for (final e in m.entries) '${e.key}': _plain(e.value)},
    YamlList l => [for (final v in l) _plain(v)],
    _ => node,
  };
}
