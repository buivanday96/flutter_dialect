import '../config/forge_config.dart';
import 'conventions.dart';
import 'scanner.dart';

/// Everything FlutterForge knows about a project's conventions.
class ProjectContext {
  ProjectContext._({
    required this.name,
    required this.dartSdk,
    required this.flutterSdk,
    required this.platforms,
    required this.conventions,
    required this.apiClient,
    required this.featuresPath,
    required this.naming,
    required this.mocks,
    required this.goldens,
    required this.testFileCount,
    required this.hasConfig,
  });

  /// Scans [root] and applies its `.flutterforge.yaml`, if any.
  factory ProjectContext.load(String root) =>
      ProjectContext.build(ProjectScanner().scan(root));

  /// Builds a context from [scan]. [config] defaults to the scanned
  /// `.flutterforge.yaml`; explicit config always beats detection.
  factory ProjectContext.build(ScanResult scan, {ForgeConfig? config}) {
    config ??= scan.configYaml == null
        ? null
        : ForgeConfig.parse(scan.configYaml!);

    final state = detectState(scan);
    final layout = detectLayout(scan);
    final detected = <String, Detection>{
      'layout': layout.layout,
      'state': state,
      'router': detectRouter(scan),
      'network': detectNetwork(scan),
      'di': detectDi(scan, state),
      'models': detectModels(scan),
      'repository': detectRepository(scan),
    };
    detected['json_methods'] = detectJsonMethods(scan, detected['models']!);
    final conventions = {
      for (final e in detected.entries)
        e.key: switch (config?.conventions[e.key]) {
          final String v => Detection.config(v),
          null => e.value,
        },
    };

    final env = scan.pubspec['environment'];
    String? envValue(String key) =>
        env is Map && env[key] != null ? '${env[key]}' : null;
    final configApi = config?.paths['api_client'];

    return ProjectContext._(
      name: '${scan.pubspec['name'] ?? ''}',
      dartSdk: envValue('sdk'),
      flutterSdk: envValue('flutter'),
      platforms: detectPlatforms(scan),
      conventions: conventions,
      apiClient: configApi != null
          ? Detection.config(configApi)
          : detectApiClient(scan),
      featuresPath: config?.paths['features'] ?? layout.featuresPath,
      naming: detectNaming(scan),
      mocks: detectMocks(scan),
      goldens: detectGoldens(scan),
      testFileCount: scan.testFiles.length,
      hasConfig: config != null,
    );
  }

  final String name;
  final String? dartSdk;
  final String? flutterSdk;
  final List<String> platforms;

  /// Keyed by the `.flutterforge.yaml` convention names, in a fixed order.
  final Map<String, Detection> conventions;

  /// Path of the project's own HTTP wrapper class.
  final Detection apiClient;
  final String? featuresPath;

  /// File suffix → count, most used first.
  final Map<String, int> naming;
  final Detection mocks;
  final bool goldens;
  final int testFileCount;
  final bool hasConfig;

  Detection get layout => conventions['layout']!;
  Detection get state => conventions['state']!;
  Detection get router => conventions['router']!;
  Detection get network => conventions['network']!;
  Detection get di => conventions['di']!;
  Detection get models => conventions['models']!;
  Detection get repository => conventions['repository']!;

  /// `fromJson/toJson` or `fromMap/toMap`.
  Detection get jsonMethods => conventions['json_methods']!;

  Map<String, Object?> toJson() => {
    'name': name,
    'sdk': {'dart': dartSdk, 'flutter': flutterSdk},
    'platforms': platforms,
    'config': hasConfig,
    'conventions': {
      for (final e in conventions.entries) e.key: e.value.toJson(),
    },
    'apiClient': apiClient.toJson(),
    'paths': {'features': featuresPath},
    'naming': naming,
    'testing': {
      'mocks': mocks.toJson(),
      'goldens': goldens,
      'testFiles': testFileCount,
    },
  };

  /// Short markdown rules an AI agent can follow. Unknown items are left out.
  String toAgentRules() {
    final sections = <String, List<String>>{};
    void add(String section, String rule) =>
        (sections[section] ??= []).add(rule);

    final screen = _topSuffix(['_page', '_screen', '_view']);
    final holder = _topSuffix(switch (state.value) {
      'bloc' => ['_bloc', '_cubit'],
      'riverpod' => ['_notifier', '_provider', '_controller'],
      'getx' => ['_controller'],
      _ => ['_controller', '_notifier', '_provider', '_view_model', '_store'],
    });
    final holderNote = holder == null ? '' : ' Name the file `*$holder.dart`.';

    switch (state.value) {
      case 'set-state':
        add(
          'State management',
          'Use StatefulWidget + setState. Do not add a state-management package.',
        );
      case 'provider':
        add(
          'State management',
          'Use ChangeNotifier classes exposed with Provider '
              '(`context.watch` / `context.read`). Do not add Riverpod, BLoC '
              'or GetX.$holderNote',
        );
      case 'riverpod':
        add(
          'State management',
          'Use Riverpod providers and Notifier classes; widgets are '
              'ConsumerWidget / ConsumerStatefulWidget.$holderNote',
        );
      case 'bloc':
        add(
          'State management',
          'Use flutter_bloc (Bloc/Cubit) with BlocProvider / BlocBuilder.'
              '$holderNote',
        );
      case 'getx':
        add(
          'State management',
          'Use GetX controllers (GetxController + Obx).$holderNote',
        );
    }

    final features = featuresPath ?? 'lib/features';
    switch (layout.value) {
      case 'flat-feature':
        add(
          'Folder layout',
          'One folder per feature: `$features/<feature>/`, with all files '
              'directly inside. No data/domain/presentation subfolders.',
        );
      case 'layered-feature':
        add(
          'Folder layout',
          'One folder per feature: `$features/<feature>/` split into '
              '`data/`, `domain/` and `presentation/`.',
        );
      case 'layer-first':
        add(
          'Folder layout',
          'Files are grouped by type at the top of `lib/` (models, screens, '
              'services…), not by feature. Put new files in the matching '
              'existing folder.',
        );
    }

    final client = apiClient.value;
    final viaClient = client == null
        ? ''
        : ' Go through the existing client in `$client`; do not create new '
              'HTTP client instances.';
    switch (network.value) {
      case 'dio':
        add('Networking', 'Use Dio.$viaClient');
      case 'http':
        add('Networking', 'Use package:http.$viaClient');
      case 'retrofit':
        add(
          'Networking',
          'Declare endpoints as Retrofit interfaces (@RestApi) on Dio.$viaClient',
        );
      case 'chopper':
        add('Networking', 'Declare endpoints as Chopper services.$viaClient');
    }

    switch (repository.value) {
      case 'concrete':
        add(
          'Repositories',
          'Repositories are concrete classes. Do not add an abstract '
              'interface + Impl pair.',
        );
      case 'interface+impl':
        add(
          'Repositories',
          'Each repository is an abstract interface plus a `*Impl` class '
              'that implements it.',
        );
    }

    switch (models.value) {
      case 'hand-written':
        final (from, to) = jsonMethods.value == 'fromMap/toMap'
            ? ('fromMap', 'toMap')
            : ('fromJson', 'toJson');
        add(
          'Models',
          'Models are hand-written classes with '
              '`factory X.$from(Map<String, dynamic>)` and `$to()`. No code '
              'generation (no freezed / json_serializable).',
        );
      case 'freezed':
        add(
          'Models',
          'Models use freezed (`@freezed`) with json_serializable; run '
              'build_runner after changes.',
        );
      case 'json_serializable':
        add(
          'Models',
          'Models use `@JsonSerializable()`; run build_runner after changes.',
        );
    }

    switch (router.value) {
      case 'go_router':
        add('Routing', 'Add routes to the existing GoRouter configuration.');
      case 'auto_route':
        add('Routing', 'Use auto_route (`@RoutePage`) and regenerate routes.');
      case 'navigator':
        add('Routing', 'Use Navigator / MaterialPageRoute; no router package.');
    }

    switch (di.value) {
      case 'get_it':
        add('Dependency injection', 'Register dependencies with get_it.');
      case 'injectable':
        add(
          'Dependency injection',
          'Annotate classes with injectable (`@injectable`, `@singleton`) and '
              'regenerate.',
        );
      case 'provider':
        add(
          'Dependency injection',
          'Provide dependencies through Provider / MultiProvider.',
        );
      case 'constructor':
        add(
          'Dependency injection',
          'Pass dependencies through constructors; no DI container.',
        );
    }

    final namingRules = [
      if (screen != null) 'screens end in `$screen.dart`',
      if (holder != null) 'state classes end in `$holder.dart`',
      if (naming.containsKey('_repository'))
        'repositories end in `_repository.dart`',
      if (naming.containsKey('_models')) 'models live in `*_models.dart`',
    ];
    if (namingRules.isNotEmpty) {
      final text = namingRules.join('; ');
      add('File naming', '${text[0].toUpperCase()}${text.substring(1)}.');
    }

    if (mocks.value != null) {
      add(
        'Tests',
        'Mock with ${mocks.value}.${goldens ? ' Golden tests are in use.' : ''}',
      );
    }

    final b = StringBuffer()
      ..writeln('# Project conventions${name.isEmpty ? '' : ': $name'}')
      ..writeln()
      ..writeln(
        '> Generated by FlutterForge from this repository. Follow these '
        'rules when adding or changing code. Anything not listed: copy the '
        'style of nearby files.',
      );
    sections.forEach((title, rules) {
      b
        ..writeln()
        ..writeln('## $title');
      for (final r in rules) {
        b.writeln('- $r');
      }
    });
    return b.toString();
  }

  String? _topSuffix(List<String> candidates) {
    String? best;
    for (final s in candidates) {
      final n = naming[s] ?? 0;
      if (n > 0 && (best == null || n > naming[best]!)) best = s;
    }
    return best;
  }
}
