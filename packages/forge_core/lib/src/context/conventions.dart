import 'package:path/path.dart' as p;

import 'scanner.dart';

/// One detected (or configured) convention.
///
/// [value] is `null` when nothing in the project points either way;
/// unknown stays unknown, it is never guessed.
class Detection {
  const Detection(
    this.value,
    this.confidence,
    this.evidence, {
    this.source = 'detected',
  });

  const Detection.unknown()
    : value = null,
      confidence = 0,
      evidence = const [],
      source = 'none';

  const Detection.config(String this.value)
    : confidence = 1,
      evidence = const ['.flutterforge.yaml'],
      source = 'config';

  final String? value;

  /// 0–1. Only explicit configuration reaches 1.
  final double confidence;

  /// Project-relative paths that support [value].
  final List<String> evidence;

  /// `detected`, `config` or `none`.
  final String source;

  bool get isKnown => value != null;

  Map<String, Object?> toJson() => {
    'value': value,
    'confidence': confidence,
    'source': source,
    'evidence': evidence,
  };
}

const _maxEvidence = 4;

double _conf(double base, double share) =>
    (((base + (0.95 - base) * share) * 100).round()) / 100;

List<String> _evidence(Iterable<String> head, Iterable<String> files) {
  final out = <String>[...head];
  for (final f in files) {
    if (out.length >= _maxEvidence + head.length) break;
    if (!out.contains(f)) out.add(f);
  }
  return out;
}

List<String> _filesMatching(ScanResult s, RegExp re) => [
  for (final f in s.libFiles)
    if (re.hasMatch(f.content)) f.path,
];

/// A choice between libraries. [packages] are pub package names whose
/// presence and imports count towards the option; [markers] are code
/// patterns that count too (e.g. `extends ChangeNotifier`).
class _Option {
  const _Option(this.value, this.packages, [this.marker]);
  final String value;
  final List<String> packages;
  final RegExp? marker;
}

/// Picks the declared option used by the most files. Earlier options win
/// ties. Returns `null` when none of the packages is declared.
Detection? _pickDeclared(ScanResult s, List<_Option> options) {
  final declared = [
    for (final o in options)
      if (o.packages.any(s.hasDependency)) o,
  ];
  if (declared.isEmpty) return null;

  final users = <String, List<String>>{};
  for (final o in declared) {
    final marked = o.marker == null ? <String>[] : _filesMatching(s, o.marker!);
    final importing = [
      for (final f in s.libFiles)
        if (o.packages.any(f.importsPackage)) f.path,
    ];
    users[o.value] = [
      ...marked,
      for (final f in importing)
        if (!marked.contains(f)) f,
    ];
  }

  final total = users.values.fold<int>(0, (n, u) => n + u.length);
  if (total == 0) {
    // Declared but never used: weak signal.
    return Detection(declared.first.value, 0.3, const ['pubspec.yaml']);
  }
  var best = declared.first;
  for (final o in declared) {
    if (users[o.value]!.length > users[best.value]!.length) best = o;
  }
  final used = users[best.value]!;
  return Detection(
    best.value,
    _conf(0.4, used.length / total),
    _evidence(['pubspec.yaml'], used),
  );
}

Detection detectState(ScanResult s) {
  final picked = _pickDeclared(s, [
    _Option('riverpod', [
      'flutter_riverpod',
      'hooks_riverpod',
      'riverpod',
    ], RegExp(r'extends\s+(Auto\w*)?(State|Async)?Notifier\b|@riverpod\b')),
    _Option('bloc', [
      'flutter_bloc',
      'bloc',
    ], RegExp(r'extends\s+(Bloc|Cubit)<')),
    _Option('getx', ['get'], RegExp(r'extends\s+GetxController\b')),
    _Option('provider', [
      'provider',
    ], RegExp(r'(extends|with)\s+ChangeNotifier\b')),
  ]);
  if (picked != null) return picked;
  final users = _filesMatching(s, RegExp(r'\bsetState\s*\('));
  if (users.isNotEmpty) {
    return Detection('set-state', 0.8, _evidence(const [], users));
  }
  return const Detection.unknown();
}

Detection detectRouter(ScanResult s) {
  final picked = _pickDeclared(s, const [
    _Option('go_router', ['go_router']),
    _Option('auto_route', ['auto_route']),
  ]);
  if (picked != null) return picked;
  final users = _filesMatching(
    s,
    RegExp(r'\bNavigator\s*\.|\bMaterialPageRoute\b'),
  );
  if (users.isNotEmpty) {
    return Detection('navigator', 0.7, _evidence(const [], users));
  }
  return const Detection.unknown();
}

Detection detectNetwork(ScanResult s) {
  // Code generators sit on top of an HTTP client; if one is in use it is
  // the convention, even when the raw client is imported more often.
  final generator = _pickDeclared(s, const [
    _Option('retrofit', ['retrofit']),
    _Option('chopper', ['chopper']),
  ]);
  if (generator != null && generator.confidence > 0.3) return generator;
  return _pickDeclared(s, const [
        _Option('dio', ['dio']),
        _Option('http', ['http']),
      ]) ??
      generator ??
      const Detection.unknown();
}

Detection detectDi(ScanResult s, Detection state) {
  final picked = _pickDeclared(s, const [
    _Option('injectable', ['injectable']),
    _Option('get_it', ['get_it']),
  ]);
  if (picked != null && picked.confidence > 0.3) return picked;
  if (state.value == 'provider') {
    final users = _filesMatching(
      s,
      RegExp(r'\b(Multi|ChangeNotifier|Proxy)?Provider(<[^>]*>)?\s*\('),
    );
    if (users.isNotEmpty) {
      return Detection('provider', 0.8, _evidence(const [], users));
    }
  }
  if (state.value == 'riverpod') {
    return Detection('riverpod', 0.7, state.evidence);
  }
  if (s.libFiles.isEmpty) return const Detection.unknown();
  return const Detection('constructor', 0.5, []);
}

const _featureRoots = [
  'lib/features',
  'lib/feature',
  'lib/modules',
  'lib/src/features',
];
const _layerSubdirs = ['data', 'domain', 'presentation', 'application'];
const _layerFirstDirs = {
  'api',
  'bloc',
  'blocs',
  'controllers',
  'cubits',
  'data',
  'http',
  'model',
  'models',
  'pages',
  'provider',
  'providers',
  'repositories',
  'repository',
  'screen',
  'screens',
  'services',
  'viewmodels',
  'views',
  'widgets',
};

/// Layout plus the directory that holds features (if any).
({Detection layout, String? featuresPath}) detectLayout(ScanResult s) {
  final dirs = s.libDirs.toSet();
  for (final root in _featureRoots) {
    if (!dirs.contains(root)) continue;
    final features = [
      for (final d in s.libDirs)
        if (p.posix.dirname(d) == root) d,
    ];
    final layered = <String>[];
    final flat = <String>[];
    for (final f in features) {
      if (_layerSubdirs.any((l) => dirs.contains('$f/$l'))) {
        layered.add(f);
      } else if (s.libFiles.any((x) => p.posix.dirname(x.path) == f)) {
        flat.add(f);
      }
    }
    final total = layered.length + flat.length;
    if (total == 0) continue;
    final isLayered = layered.length > flat.length;
    final winners = isLayered ? layered : flat;
    return (
      layout: Detection(
        isLayered ? 'layered-feature' : 'flat-feature',
        _conf(0.5, winners.length / total),
        _evidence(const [], winners),
      ),
      featuresPath: root,
    );
  }

  final layers = [
    for (final d in s.libDirs)
      if (p.posix.dirname(d) == 'lib' &&
          _layerFirstDirs.contains(p.posix.basename(d)))
        d,
  ];
  if (layers.length >= 2) {
    return (
      layout: Detection(
        'layer-first',
        (layers.length * 0.1 + 0.4).clamp(0, 0.9).toDouble(),
        _evidence(const [], layers),
      ),
      featuresPath: null,
    );
  }
  return (layout: const Detection.unknown(), featuresPath: null);
}

Detection detectModels(ScanResult s) {
  final freezed =
      s.hasDependency('freezed_annotation') || s.hasDependency('freezed')
      ? _filesMatching(s, RegExp(r'@freezed\b|@Freezed\('))
      : const <String>[];
  final jsonSer =
      s.hasDependency('json_annotation') || s.hasDependency('json_serializable')
      ? _filesMatching(s, RegExp(r'@JsonSerializable\b'))
      : const <String>[];
  final handWritten = _filesMatching(
    s,
    RegExp(r'factory\s+\w+\.from(Json|Map)\s*\([^)]*\)\s*(=>|\{)(?!\s*_\$)'),
  );
  final all = {...freezed, ...jsonSer, ...handWritten};
  if (all.isEmpty) return const Detection.unknown();

  final (value, files) = freezed.isNotEmpty
      ? ('freezed', freezed)
      : jsonSer.isNotEmpty
      ? ('json_serializable', jsonSer)
      : ('hand-written', handWritten);
  return Detection(
    value,
    _conf(0.5, files.length / all.length),
    _evidence(const [], files),
  );
}

/// For hand-written models: `fromJson/toJson` or `fromMap/toMap`.
/// Generated models always use fromJson/toJson, so they don't count.
Detection detectJsonMethods(ScanResult s, Detection models) {
  if (models.value == null) return const Detection.unknown();
  if (models.value != 'hand-written') {
    return Detection('fromJson/toJson', models.confidence, models.evidence);
  }
  final decl = RegExp(
    r'factory\s+\w+\.(fromJson|fromMap)\s*\(|\b(toJson|toMap)\s*\(\s*\)\s*(=>|\{)',
  );
  final counts = {'Json': <String>[], 'Map': <String>[]};
  var json = 0, map = 0;
  for (final f in s.libFiles) {
    for (final m in decl.allMatches(f.content)) {
      final name = m.group(1) ?? m.group(2)!;
      final key = name.endsWith('Map') ? 'Map' : 'Json';
      key == 'Map' ? map++ : json++;
      if (!counts[key]!.contains(f.path)) counts[key]!.add(f.path);
    }
  }
  if (json + map == 0) return const Detection.unknown();
  final useMap = map > json;
  return Detection(
    useMap ? 'fromMap/toMap' : 'fromJson/toJson',
    _conf(0.5, (useMap ? map : json) / (json + map)),
    _evidence(const [], counts[useMap ? 'Map' : 'Json']!),
  );
}

final _classRe = RegExp(
  r'^[ \t]*((?:abstract|interface|base|final|sealed)\s+)*class\s+(\w+)([^{]*)\{',
  multiLine: true,
);
final _implementsRepo = RegExp(r'implements\s+[\w, <>]*Repository\b');

Detection detectRepository(ScanResult s) {
  final interfaces = <String>[];
  final impls = <String>[];
  final concretes = <String>[];
  for (final f in s.libFiles) {
    for (final m in _classRe.allMatches(f.content)) {
      final modifiers = m.group(1) ?? '';
      final name = m.group(2)!;
      final clause = m.group(3)!;
      final isAbstract = RegExp(
        r'\b(abstract|interface|sealed)\b',
      ).hasMatch(modifiers);
      if (name.endsWith('Repository') && isAbstract) {
        interfaces.add(f.path);
      } else if (_implementsRepo.hasMatch(clause)) {
        impls.add(f.path);
      } else if (name.endsWith('Repository')) {
        concretes.add(f.path);
      }
    }
  }
  if (interfaces.isNotEmpty && impls.isNotEmpty) {
    final n = interfaces.length + impls.length;
    return Detection(
      'interface+impl',
      _conf(0.5, n / (n + concretes.length)),
      _evidence(const [], [...interfaces, ...impls]),
    );
  }
  if (concretes.isNotEmpty) {
    return Detection(
      'concrete',
      _conf(0.5, concretes.length / (concretes.length + interfaces.length)),
      _evidence(const [], concretes),
    );
  }
  return const Detection.unknown();
}

/// The project's own HTTP wrapper, if it has one. Value is a path.
Detection detectApiClient(ScanResult s) {
  for (final f in s.libFiles) {
    if (f.basename == 'api_client' || f.basename.endsWith('_api_client')) {
      return Detection(f.path, 0.9, [f.path]);
    }
  }
  final re = RegExp(r'^class\s+\w*Api(Client|Service)\b', multiLine: true);
  for (final f in s.libFiles) {
    if (re.hasMatch(f.content)) return Detection(f.path, 0.7, [f.path]);
  }
  return const Detection.unknown();
}

Detection detectMocks(ScanResult s) {
  for (final pkg in ['mocktail', 'mockito']) {
    if (s.hasDependency(pkg)) {
      final users = [
        for (final f in s.testFiles)
          if (f.importsPackage(pkg)) f.path,
      ];
      return Detection(
        pkg,
        users.isEmpty ? 0.5 : 0.9,
        _evidence(['pubspec.yaml'], users),
      );
    }
  }
  return const Detection.unknown();
}

bool detectGoldens(ScanResult s) =>
    s.testFiles.any((f) => f.content.contains('matchesGoldenFile'));

/// Longest first so `_view_model` wins over `_model`.
const _suffixes = [
  '_view_model',
  '_extensions',
  '_controller',
  '_repository',
  '_viewmodel',
  '_notifier',
  '_provider',
  '_service',
  '_screen',
  '_models',
  '_widget',
  '_client',
  '_event',
  '_model',
  '_state',
  '_store',
  '_utils',
  '_cubit',
  '_bloc',
  '_impl',
  '_page',
  '_repo',
  '_util',
  '_view',
  '_api',
];

/// File-name suffix → number of lib files using it, most used first.
Map<String, int> detectNaming(ScanResult s) {
  final counts = <String, int>{};
  for (final f in s.libFiles) {
    for (final suffix in _suffixes) {
      if (f.basename.endsWith(suffix) && f.basename != suffix.substring(1)) {
        counts[suffix] = (counts[suffix] ?? 0) + 1;
        break;
      }
    }
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final c = counts[b]!.compareTo(counts[a]!);
      return c != 0 ? c : a.compareTo(b);
    });
  return {for (final k in keys) k: counts[k]!};
}

const _platforms = ['android', 'ios', 'web', 'macos', 'linux', 'windows'];

List<String> detectPlatforms(ScanResult s) => [
  for (final pl in _platforms)
    if (s.rootEntries.contains(pl)) pl,
];
