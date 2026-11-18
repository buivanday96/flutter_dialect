import 'package:path/path.dart' as p;

import 'scanner.dart';

/// An existing file an agent can copy the style of.
class CodeExample {
  CodeExample({
    required this.path,
    required this.lines,
    required this.content,
    required this.truncated,
  });

  final String path;
  final int lines;
  final String content;
  final bool truncated;

  Map<String, Object?> toJson() => {
    'path': path,
    'lines': lines,
    'truncated': truncated,
    'content': content,
  };
}

/// Kinds [findSimilarCode] understands, with the words that select them.
const codeKinds = <String, List<String>>{
  'repository': ['repository', 'repo', 'data source', 'datasource'],
  'state': [
    'state',
    'notifier',
    'controller',
    'provider',
    'bloc',
    'cubit',
    'store',
    'view model',
    'viewmodel',
  ],
  // After 'state', so "view model" is state, not screen.
  'screen': ['screen', 'page', 'view', 'ui'],
  'model': ['model', 'models', 'dto', 'entity'],
  'widget': ['widget', 'component'],
  'service': ['service', 'client', 'api'],
  'test': ['test', 'spec'],
};

/// Maps free text such as "a ChangeNotifier controller" to a [codeKinds]
/// key, or `null`.
String? normalizeKind(String text) {
  final t = text.toLowerCase().replaceAll(RegExp(r'[_-]'), ' ');
  for (final MapEntry(key: kind, value: words) in codeKinds.entries) {
    if (words.any((w) => RegExp('\\b${RegExp.escape(w)}s?\\b').hasMatch(t))) {
      return kind;
    }
  }
  return null;
}

final _markers = <String, RegExp>{
  'repository': RegExp(r'class\s+\w*Repository(Impl)?\b'),
  'screen': RegExp(r'class\s+\w+(Screen|Page|View)\s+extends\s+\w*Widget'),
  'state': RegExp(
    r'(extends|with)\s+(ChangeNotifier|Cubit<|Bloc<|StateNotifier<|'
    r'Notifier<|AsyncNotifier<|GetxController)',
  ),
  'model': RegExp(
    r'factory\s+\w+\.from(Json|Map)\s*\(|@freezed|@JsonSerializable',
  ),
  'widget': RegExp(r'class\s+\w+\s+extends\s+(Stateless|Stateful)Widget'),
  'service': RegExp(r'class\s+\w*(Service|Client|Api)\b'),
};

const _suffixes = <String, List<String>>{
  'repository': ['_repository', '_repository_impl', '_repo'],
  'screen': ['_screen', '_page', '_view'],
  'state': [
    '_controller',
    '_notifier',
    '_provider',
    '_bloc',
    '_cubit',
    '_store',
    '_view_model',
    '_viewmodel',
  ],
  'model': ['_models', '_model'],
  'widget': ['_widget', '_widgets'],
  'service': ['_service', '_client', '_api'],
};

final _viewModel = RegExp(r'_view_?model$');
final _fake = RegExp(
  r'(^|/|_)(fake|fakes|mock|mocks|stub|stubs|testing)(/|_|\.)',
);

/// Up to [limit] existing files of [kind] (a [codeKinds] key), preferring
/// mid-sized ones (about 100 lines) from different folders. Deterministic.
List<CodeExample> findSimilarCode(
  ScanResult s,
  String kind, {
  int limit = 2,
  int maxLines = 250,
}) {
  final pool = kind == 'test' ? s.testFiles : s.libFiles;
  final suffixes = _suffixes[kind] ?? const [];
  final marker = _markers[kind];
  final candidates = [
    for (final f in pool)
      if (!(kind == 'model' && _viewModel.hasMatch(f.basename)) &&
          (kind == 'test' ||
              suffixes.any(f.basename.endsWith) ||
              (marker != null && marker.hasMatch(f.content))))
        f,
  ];
  int lineCount(SourceFile f) => '\n'.allMatches(f.content).length + 1;
  // Files named by convention first, then closest to ~100 lines.
  int score(SourceFile f) =>
      (suffixes.any(f.basename.endsWith) ? 0 : 1000) +
      (lineCount(f) - 100).abs() +
      (lineCount(f) < 15 ? 500 : 0) +
      // Fakes and mocks are poor examples of production style.
      (kind != 'test' && _fake.hasMatch(f.path) ? 2000 : 0);
  candidates.sort((a, b) {
    final c = score(a).compareTo(score(b));
    return c != 0 ? c : a.path.compareTo(b.path);
  });

  final picked = <SourceFile>[];
  final dirs = <String>{};
  for (final f in candidates) {
    if (picked.length >= limit) break;
    if (dirs.add(p.posix.dirname(f.path))) picked.add(f);
  }
  for (final f in candidates) {
    if (picked.length >= limit) break;
    if (!picked.contains(f)) picked.add(f);
  }
  return [for (final f in picked) _example(f, lineCount(f), maxLines)];
}

CodeExample _example(SourceFile f, int lines, int maxLines) {
  final truncated = lines > maxLines;
  return CodeExample(
    path: f.path,
    lines: lines,
    truncated: truncated,
    content: truncated
        ? '${f.content.split('\n').take(maxLines).join('\n')}\n// … truncated'
        : f.content,
  );
}
