import 'dart:io';

import 'package:path/path.dart' as p;

import 'change_plan.dart';

/// The working tree is dirty or not under git; git is the safety net.
class DirtyTreeException implements Exception {
  DirtyTreeException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ApplyResult {
  ApplyResult({
    required this.written,
    required this.conflicts,
    required this.stale,
  });

  final List<String> written;

  /// Conflicts already known when the plan was made; not written.
  final List<String> conflicts;

  /// Files that changed on disk since the plan was made; not written.
  final List<String> stale;

  bool get clean => conflicts.isEmpty && stale.isEmpty;
}

/// Writes [plan]. Refuses a dirty (or non-git) tree unless [force]; skips
/// conflicts and any file that changed since the plan was made. Never
/// deletes anything.
ApplyResult applyPlan(ChangePlan plan, {bool force = false}) {
  if (!force) _checkGitClean(plan.root);
  final written = <String>[];
  final conflicts = <String>[];
  final stale = <String>[];
  for (final c in plan.changes) {
    checkWritablePath(c.path);
    final file = File(p.join(plan.root, c.path));
    switch (c.kind) {
      case ChangeKind.unchanged:
        continue;
      case ChangeKind.conflict:
        conflicts.add(c.path);
        continue;
      case ChangeKind.create:
        if (file.existsSync()) {
          stale.add(c.path);
          continue;
        }
      case ChangeKind.modify:
        if (!file.existsSync() || file.readAsStringSync() != c.before) {
          stale.add(c.path);
          continue;
        }
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(c.after);
    written.add(c.path);
  }
  return ApplyResult(written: written, conflicts: conflicts, stale: stale);
}

void _checkGitClean(String root) {
  final ProcessResult result;
  try {
    result = Process.runSync('git', [
      'status',
      '--porcelain',
    ], workingDirectory: root);
  } on ProcessException {
    throw DirtyTreeException(
      'git is not available; use --force to write anyway.',
    );
  }
  if (result.exitCode != 0) {
    throw DirtyTreeException(
      '$root is not a git repository; use --force to write anyway.',
    );
  }
  if ('${result.stdout}'.trim().isNotEmpty) {
    throw DirtyTreeException(
      'Working tree has uncommitted changes; commit or stash them, or use '
      '--force.',
    );
  }
}
