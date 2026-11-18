import 'dart:io';

import 'package:path/path.dart' as p;

import 'diff.dart';

enum ChangeKind {
  /// New file.
  create,

  /// Replaces a file whose current content is [FileChange.before].
  modify,

  /// File exists with the same content; nothing to do.
  unchanged,

  /// File exists with different content; skipped (no merge in MVP).
  conflict,
}

class FileChange {
  const FileChange({
    required this.path,
    required this.kind,
    required this.after,
    this.before,
  });

  factory FileChange.fromJson(Map<String, Object?> json) => FileChange(
    path: json['path'] as String,
    kind: ChangeKind.values.byName(json['kind'] as String),
    before: json['before'] as String?,
    after: json['after'] as String,
  );

  /// Project-relative, `/`-separated.
  final String path;
  final ChangeKind kind;

  /// Content on disk when the plan was made (`null` if the file was absent).
  final String? before;
  final String after;

  Map<String, Object?> toJson() => {
    'path': path,
    'kind': kind.name,
    'before': before,
    'after': after,
  };
}

/// What a command would write, shown as a diff before anything is written.
class ChangePlan {
  ChangePlan({
    required this.root,
    required this.changes,
    this.warnings = const [],
  });

  /// Compares [files] (project-relative path → content) with disk.
  ///
  /// Paths must be under `lib/` or `test/`. Existing files that differ are
  /// conflicts, unless listed in [replace], which makes them modifications.
  factory ChangePlan.build(
    String root,
    Map<String, String> files, {
    List<String> warnings = const [],
    Set<String> replace = const {},
  }) {
    final changes = <FileChange>[];
    for (final MapEntry(key: path, value: after) in files.entries) {
      checkWritablePath(path);
      final file = File(p.join(root, path));
      final before = file.existsSync() ? file.readAsStringSync() : null;
      final kind = before == null
          ? ChangeKind.create
          : before == after
          ? ChangeKind.unchanged
          : replace.contains(path)
          ? ChangeKind.modify
          : ChangeKind.conflict;
      changes.add(
        FileChange(path: path, kind: kind, before: before, after: after),
      );
    }
    return ChangePlan(
      root: p.normalize(p.absolute(root)),
      changes: changes,
      warnings: warnings,
    );
  }

  factory ChangePlan.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported plan version');
    }
    return ChangePlan(
      root: json['root'] as String,
      warnings: [for (final w in json['warnings'] as List) w as String],
      changes: [
        for (final c in json['changes'] as List)
          FileChange.fromJson((c as Map).cast<String, Object?>()),
      ],
    );
  }

  final String root;
  final List<FileChange> changes;
  final List<String> warnings;

  bool get hasConflicts => changes.any((c) => c.kind == ChangeKind.conflict);

  /// Whether applying would write anything.
  bool get hasWrites => changes.any(
    (c) => c.kind == ChangeKind.create || c.kind == ChangeKind.modify,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'root': root,
    'warnings': warnings,
    'changes': [for (final c in changes) c.toJson()],
  };

  /// One line per file, e.g. `create  lib/features/x/x_models.dart`.
  String summary() => [
    for (final c in changes) '${c.kind.name.padRight(9)} ${c.path}',
  ].join('\n');

  /// Unified diff of every change; conflicts are diffed but marked.
  String diff() {
    final b = StringBuffer();
    for (final c in changes) {
      switch (c.kind) {
        case ChangeKind.unchanged:
          b.writeln('# unchanged: ${c.path}');
        case ChangeKind.conflict:
          b
            ..writeln(
              '# CONFLICT: ${c.path} exists and differs; it will be skipped.',
            )
            ..write(
              unifiedDiff(
                c.before!,
                c.after,
                fromName: 'a/${c.path}',
                toName: 'b/${c.path}',
              ),
            );
        case ChangeKind.create:
          b.write(
            unifiedDiff(
              '',
              c.after,
              fromName: '/dev/null',
              toName: 'b/${c.path}',
            ),
          );
        case ChangeKind.modify:
          b.write(
            unifiedDiff(
              c.before!,
              c.after,
              fromName: 'a/${c.path}',
              toName: 'b/${c.path}',
            ),
          );
      }
    }
    return b.toString();
  }
}

/// Throws [ArgumentError] unless [path] is a relative path inside `lib/` or
/// `test/`.
void checkWritablePath(String path) {
  final normal = p.posix.normalize(path);
  if (p.posix.isAbsolute(path) ||
      normal != path ||
      path.contains('\\') ||
      !(normal.startsWith('lib/') || normal.startsWith('test/'))) {
    throw ArgumentError.value(
      path,
      'path',
      'Flutter Dialect only writes inside lib/ and test/',
    );
  }
}
