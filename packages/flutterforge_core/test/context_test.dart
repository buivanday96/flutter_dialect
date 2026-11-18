import 'dart:convert';
import 'dart:io';

import 'package:flutterforge_core/flutterforge_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String fixture(String name) => p.normalize(
  p.join(Directory.current.path, '..', '..', 'test', 'fixtures', name),
);

ProjectContext load(String name, {ForgeConfig? config}) =>
    ProjectContext.build(ProjectScanner().scan(fixture(name)), config: config);

void main() {
  group('flat_provider', () {
    late ProjectContext ctx;
    setUpAll(() => ctx = load('flat_provider'));

    test('project info', () {
      expect(ctx.name, 'flat_shop');
      expect(ctx.dartSdk, '^3.5.0');
      expect(ctx.flutterSdk, '>=3.24.0');
      expect(ctx.platforms, ['android', 'ios']);
    });

    test('conventions', () {
      expect(ctx.state.value, 'provider');
      expect(ctx.router.value, 'go_router');
      expect(ctx.network.value, 'dio');
      expect(ctx.di.value, 'provider');
      expect(ctx.layout.value, 'flat-feature');
      expect(ctx.models.value, 'hand-written');
      expect(ctx.repository.value, 'concrete');
      expect(ctx.jsonMethods.value, 'fromJson/toJson');
      expect(ctx.apiClient.value, 'lib/core/api_client.dart');
      expect(ctx.featuresPath, 'lib/features');
    });

    test('naming and tests', () {
      expect(ctx.naming['_controller'], 2);
      expect(ctx.naming['_page'], 2);
      expect(ctx.mocks.value, 'mocktail');
      expect(ctx.goldens, isFalse);
    });

    test('evidence points at real files', () {
      expect(ctx.state.evidence, contains('pubspec.yaml'));
      expect(
        ctx.state.evidence,
        contains('lib/features/products/products_controller.dart'),
      );
      expect(ctx.state.confidence, greaterThan(0.8));
    });

    test('agent rules mention the house style', () {
      final rules = ctx.toAgentRules();
      expect(rules, contains('ChangeNotifier'));
      expect(rules, contains('lib/features/<feature>/'));
      expect(rules, contains('lib/core/api_client.dart'));
      expect(rules, contains('concrete'));
      expect(rules, contains('_page.dart'));
    });
  });

  group('layered_riverpod', () {
    late ProjectContext ctx;
    setUpAll(() => ctx = load('layered_riverpod'));

    test('conventions', () {
      expect(ctx.state.value, 'riverpod');
      expect(ctx.router.value, 'auto_route');
      expect(ctx.network.value, 'http');
      expect(ctx.di.value, 'get_it');
      expect(ctx.layout.value, 'layered-feature');
      expect(ctx.models.value, 'freezed');
      expect(ctx.repository.value, 'interface+impl');
      expect(ctx.platforms, ['ios', 'web']);
      expect(ctx.mocks.value, 'mockito');
      expect(ctx.goldens, isTrue);
    });

    test('generated files are ignored', () {
      final files = ProjectScanner()
          .scan(fixture('layered_riverpod'))
          .libFiles
          .map((f) => f.path);
      expect(files.where((f) => f.endsWith('.freezed.dart')), isEmpty);
    });
  });

  group('bloc_layer_first', () {
    late ProjectContext ctx;
    setUpAll(() => ctx = load('bloc_layer_first'));

    test('conventions', () {
      expect(ctx.state.value, 'bloc');
      expect(ctx.router.value, isNull, reason: 'no navigation code at all');
      expect(ctx.network.value, 'retrofit');
      expect(ctx.di.value, 'injectable');
      expect(ctx.layout.value, 'layer-first');
      expect(ctx.models.value, 'json_serializable');
      expect(ctx.featuresPath, isNull);
      expect(ctx.naming['_cubit'], 1);
      expect(ctx.naming['_bloc'], 1);
    });
  });

  group('plain_set_state', () {
    late ProjectContext ctx;
    setUpAll(() => ctx = load('plain_set_state'));

    test('conventions', () {
      expect(ctx.state.value, 'set-state');
      expect(ctx.router.value, 'navigator');
      expect(ctx.di.value, 'constructor');
      expect(ctx.platforms, isEmpty);
    });

    test('unknown stays unknown', () {
      expect(ctx.network.value, isNull);
      expect(ctx.network.confidence, 0);
      expect(ctx.layout.value, isNull);
      expect(ctx.models.value, isNull);
      expect(ctx.repository.value, isNull);
      expect(ctx.mocks.value, isNull);
      expect(ctx.toAgentRules(), isNot(contains('Network')));
    });
  });

  test('fromMap/toMap models are hand-written and keep their names', () {
    final dir = Directory.systemTemp.createTempSync('ff_map');
    addTearDown(() => dir.deleteSync(recursive: true));
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: m\n');
    File(p.join(dir.path, 'lib', 'user_models.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
class User {
  User(this.id);
  factory User.fromMap(Map<String, dynamic> map) {
    return User(map['id'] as int);
  }
  final int id;
  Map<String, dynamic> toMap() => {'id': id};
}
''');
    final ctx = ProjectContext.load(dir.path);
    expect(ctx.models.value, 'hand-written');
    expect(ctx.jsonMethods.value, 'fromMap/toMap');
    expect(ctx.toAgentRules(), contains('X.fromMap'));
  });

  group('config override', () {
    test('explicit config beats detection', () {
      final config = ForgeConfig.parse('''
version: 1
conventions:
  state: riverpod
  layout: layered-feature
paths:
  features: lib/modules
''');
      final ctx = load('flat_provider', config: config);
      expect(ctx.state.value, 'riverpod');
      expect(ctx.state.confidence, 1.0);
      expect(ctx.state.source, 'config');
      expect(ctx.state.evidence, ['.flutterforge.yaml']);
      expect(ctx.layout.value, 'layered-feature');
      expect(ctx.featuresPath, 'lib/modules');
      // Untouched values keep their detection.
      expect(ctx.network.value, 'dio');
      expect(ctx.network.source, 'detected');
    });

    test('config file in project root is picked up by load()', () {
      final dir = Directory.systemTemp.createTempSync('ff_cfg');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
      File(
        p.join(dir.path, '.flutterforge.yaml'),
      ).writeAsStringSync('version: 1\nconventions:\n  network: http\n');
      expect(ProjectContext.load(dir.path).network.value, 'http');
    });

    test('rejects unknown keys and values', () {
      expect(
        () => ForgeConfig.parse('version: 1\nconventions:\n  state: mobx\n'),
        throwsFormatException,
      );
      expect(
        () => ForgeConfig.parse('version: 1\nconventions:\n  colour: red\n'),
        throwsFormatException,
      );
      expect(() => ForgeConfig.parse('version: 2\n'), throwsFormatException);
    });

    test('init yaml round-trips', () {
      final ctx = load('flat_provider');
      final yaml = ForgeConfig.fromContext(ctx).toYaml();
      final reparsed = ForgeConfig.parse(yaml);
      expect(reparsed.conventions['state'], 'provider');
      expect(reparsed.conventions['layout'], 'flat-feature');
      expect(reparsed.paths['features'], 'lib/features');
    });
  });

  test('missing pubspec is an error', () {
    final dir = Directory.systemTemp.createTempSync('ff_empty');
    addTearDown(() => dir.deleteSync(recursive: true));
    expect(
      () => ProjectScanner().scan(dir.path),
      throwsA(isA<ScanException>()),
    );
  });

  test('output is deterministic', () {
    for (final name in [
      'flat_provider',
      'layered_riverpod',
      'bloc_layer_first',
      'plain_set_state',
    ]) {
      final a = jsonEncode(load(name).toJson());
      final b = jsonEncode(load(name).toJson());
      expect(a, b, reason: name);
      expect(load(name).toAgentRules(), load(name).toAgentRules());
    }
  });
}
