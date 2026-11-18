import 'dart:io';

import 'package:forge_core/forge_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final fixtures = p.normalize(
  p.join(Directory.current.path, '..', '..', 'test', 'fixtures'),
);
final goldens = p.join(fixtures, 'goldens');
final updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

ApiDoc spec(String name) => OpenApiLoader().load(
  File(p.join(fixtures, 'specs', name)).readAsStringSync(),
);

GeneratedApi generate(String app, String specName, String tag) => ApiGenerator(
  ProjectContext.load(p.join(fixtures, app)),
).generate(spec(specName), tag: tag);

/// Copies a fixture into a temp dir.
Directory tempCopy(String name) {
  final dir = Directory.systemTemp.createTempSync('ff_api');
  addTearDown(() => dir.deleteSync(recursive: true));
  final src = p.join(fixtures, name);
  for (final e in Directory(src).listSync(recursive: true)) {
    final target = p.join(dir.path, p.relative(e.path, from: src));
    if (e is Directory) Directory(target).createSync(recursive: true);
    if (e is File && !e.path.contains('.dart_tool')) {
      File(target).parent.createSync(recursive: true);
      e.copySync(target);
    }
  }
  return dir;
}

void git(String dir, List<String> args) {
  final r = Process.runSync('git', args, workingDirectory: dir);
  if (r.exitCode != 0) throw StateError('git $args: ${r.stderr}');
}

Directory tempRepo(String fixture) {
  final dir = tempCopy(fixture);
  git(dir.path, ['init', '-q']);
  git(dir.path, ['add', '-A']);
  git(dir.path, [
    '-c',
    'user.email=t@t',
    '-c',
    'user.name=t',
    'commit',
    '-qm',
    'init',
  ]);
  return dir;
}

void main() {
  group('loader', () {
    test('schemas, types and names', () {
      final doc = spec('shop.yaml');
      final product = doc.schemas['Product']!;
      expect(product.description, 'A product in the catalog.');
      expect(product.fields.map((f) => f.name), [
        'id',
        'name',
        'price',
        'tags',
        'status',
        'category',
        'dimensions',
        'createdAt',
        'metadata',
      ]);
      String typeOf(ApiSchema s, String field) =>
          dartType(s.fields.firstWhere((f) => f.jsonName == field).type);
      expect(typeOf(product, 'tags'), 'List<String>');
      expect(typeOf(product, 'status'), 'ProductStatus');
      expect(typeOf(product, 'dimensions'), 'ProductDimensions');
      expect(typeOf(product, 'createdAt'), 'DateTime');
      expect(typeOf(product, 'metadata'), 'Map<String, dynamic>');
      expect(doc.schemas['ProductDimensions']!.fields, hasLength(2));

      final category = doc.schemas['Category']!;
      final parent = category.fields.last;
      expect(parent.name, 'parentId');
      expect(parent.jsonName, 'parent_id');
      expect(parent.nullable, isTrue);

      final status = doc.schemas['OrderStatus']!;
      expect(status.isEnum, isTrue);
      expect(status.enumValues.map((v) => v.name), [
        'pending',
        'paid',
        'inTransit',
        'newValue',
        'v2faRequired',
      ]);
      expect(
        doc.schemas['Order']!.fields.last.name,
        'classValue',
        reason: 'keywords are escaped',
      );
    });

    test('operations', () {
      final ops = spec('shop.yaml').operationsFor('products');
      expect(ops.map((o) => o.name), [
        'listProducts',
        'createProduct',
        'getProduct',
        'deleteProduct',
      ]);
      final list = ops.first;
      expect(list.queryParams.map((q) => q.name), [
        'page',
        'size',
        'status',
        'q',
      ]);
      expect(list.queryParams.last.required, isTrue);
      expect(dartType(list.response!), 'List<Product>');
      expect(dartType(ops[1].body!.type), 'CreateProductRequest');
      expect(ops[2].pathParams.single.name, 'productId');
      expect(ops[3].response, isNull);
    });

    test('unsupported features are warnings, not crashes', () {
      final doc = spec('shop.yaml');
      final payment = doc.operationsFor('orders').last;
      expect(dartType(payment.response!), 'Object?');
      expect(doc.warnings, contains(contains('oneOf')));
      expect(
        doc.warnings,
        contains(contains('header parameter "X-Request-Id"')),
      );
    });

    test('envelopes are unwrapped', () {
      final doc = spec('nus_api.yaml');
      final cartridges = doc.operationsFor('cartridge').single;
      expect(cartridges.envelope, isTrue);
      expect(dartType(cartridges.response!), 'List<Cartridge>');
      final login = doc.operationsFor('auth').single;
      expect(dartType(login.response!), 'LoginResponse');
      expect(doc.schemas['LoginResponse']!.fields.last.nullable, isTrue);
      final update = doc.operationsFor('user').single;
      expect(update.envelope, isTrue);
      expect(update.response, isNull, reason: 'data: {} means no payload');
      expect(doc.schemas.containsKey('Envelope'), isFalse);
      expect(doc.schemas.containsKey('CartridgeListResponse'), isFalse);
    });

    test('rejects swagger 2 and unknown tags', () {
      expect(
        () => OpenApiLoader().load('swagger: "2.0"\npaths: {}\n'),
        throwsFormatException,
      );
      expect(
        () => spec('shop.yaml').operationsFor('nope'),
        throwsArgumentError,
      );
    });
  });

  group('goldens', () {
    const cases = [
      ('flat_provider', 'shop.yaml', 'products'),
      ('halp_style_app', 'nus_api.yaml', 'test'),
      ('nus_style_app', 'nus_api.yaml', 'cartridge'),
      ('nus_style_app', 'nus_api.yaml', 'user'),
      ('layered_http_app', 'shop.yaml', 'orders'),
    ];
    for (final (app, specName, tag) in cases) {
      test('$app / $tag', () {
        final out = generate(app, specName, tag);
        final again = generate(app, specName, tag);
        expect(again.files, out.files, reason: 'deterministic');
        for (final MapEntry(key: path, value: content) in out.files.entries) {
          final golden = File(p.join(goldens, '${app}__$tag', path));
          if (updateGoldens) {
            golden
              ..createSync(recursive: true)
              ..writeAsStringSync(content);
          }
          expect(content, golden.readAsStringSync(), reason: path);
        }
        final expected = Directory(
          p.join(goldens, '${app}__$tag'),
        ).listSync(recursive: true).whereType<File>().length;
        expect(out.files, hasLength(expected), reason: 'stale golden files');
      });
    }

    test('file placement follows the layout', () {
      expect(generate('flat_provider', 'shop.yaml', 'products').files.keys, [
        'lib/features/products/products_models.dart',
        'lib/features/products/products_repository.dart',
      ]);
      expect(
        generate('nus_style_app', 'nus_api.yaml', 'cartridge').files.keys,
        [
          'lib/model/cartridge_models.dart',
          'lib/http/cartridge_repository.dart',
        ],
      );
      expect(generate('layered_http_app', 'shop.yaml', 'orders').files.keys, [
        'lib/features/orders/domain/orders_models.dart',
        'lib/features/orders/domain/orders_repository.dart',
        'lib/features/orders/data/orders_repository_impl.dart',
      ]);
    });

    test('model style it cannot produce is reported', () {
      final out = generate('layered_riverpod', 'shop.yaml', 'orders');
      expect(out.warnings, contains(contains('freezed')));
    });
  });

  group('change plan', () {
    test('existing files are conflicts, not overwritten', () {
      final out = generate('flat_provider', 'shop.yaml', 'products');
      final plan = ChangePlan.build(
        p.join(fixtures, 'flat_provider'),
        out.files,
      );
      expect(plan.changes.map((c) => c.kind), [
        ChangeKind.conflict,
        ChangeKind.conflict,
      ]);
    });

    test('unified diff hunks', () {
      final a = [for (var i = 1; i <= 20; i++) 'line $i'].join('\n');
      final b = a
          .replaceFirst('line 3\n', 'line 3\nnew\n')
          .replaceFirst('line 18', 'changed');
      final d = unifiedDiff('$a\n', '$b\n', fromName: 'a', toName: 'b');
      expect(d.split('\n').where((l) => l.startsWith('@@')).toList(), [
        '@@ -1,6 +1,7 @@',
        '@@ -15,6 +16,6 @@',
      ]);
      expect(d, contains('+new'));
      expect(d, contains('-line 18'));
      expect(d, contains('+changed'));
      expect(unifiedDiff('x', 'x', fromName: 'a', toName: 'b'), isEmpty);
    });

    test('creates, unchanged and conflicts', () {
      final dir = tempCopy('flat_provider');
      final ctx = ProjectContext.load(dir.path);
      final out = ApiGenerator(
        ctx,
      ).generate(spec('shop.yaml'), tag: 'products');
      final models = out.files.keys.first;
      final repo = out.files.keys.last;
      File(p.join(dir.path, models)).writeAsStringSync(out.files[models]!);
      File(p.join(dir.path, repo))
        ..createSync(recursive: true)
        ..writeAsStringSync('// mine\n');

      final plan = ChangePlan.build(dir.path, out.files);
      expect(plan.changes.map((c) => c.kind), [
        ChangeKind.unchanged,
        ChangeKind.conflict,
      ]);
      expect(plan.hasConflicts, isTrue);
      expect(plan.diff(), contains('-// mine'));
      expect(plan.diff(), contains('CONFLICT'));
    });

    test('refuses paths outside lib/ and test/', () {
      expect(
        () => ChangePlan.build('/x', {'pubspec.yaml': ''}),
        throwsArgumentError,
      );
      expect(
        () => ChangePlan.build('/x', {'lib/../../etc/passwd': ''}),
        throwsArgumentError,
      );
    });

    test('diff shows new files as additions', () {
      final out = generate('flat_provider', 'shop.yaml', 'orders');
      final plan = ChangePlan.build(
        p.join(fixtures, 'flat_provider'),
        out.files,
      );
      final diff = plan.diff();
      expect(diff, contains('--- /dev/null'));
      expect(diff, contains('+++ b/lib/features/orders/orders_models.dart'));
      expect(diff, contains('+class Order {'));
    });

    test('json round-trip', () {
      final out = generate('flat_provider', 'shop.yaml', 'products');
      final plan = ChangePlan.build(
        p.join(fixtures, 'flat_provider'),
        out.files,
        warnings: out.warnings,
      );
      final copy = ChangePlan.fromJson(plan.toJson());
      expect(copy.toJson(), plan.toJson());
    });
  });

  group('apply', () {
    ChangePlan planFor(Directory dir) {
      final ctx = ProjectContext.load(dir.path);
      final out = ApiGenerator(ctx).generate(spec('shop.yaml'), tag: 'orders');
      return ChangePlan.build(dir.path, out.files);
    }

    test('writes files in a clean repo', () {
      final dir = tempRepo('flat_provider');
      final result = applyPlan(planFor(dir));
      expect(result.written, hasLength(2));
      expect(File(p.join(dir.path, result.written.first)).existsSync(), isTrue);
    });

    test('refuses a dirty tree unless forced', () {
      final dir = tempRepo('flat_provider');
      File(p.join(dir.path, 'lib', 'main.dart')).writeAsStringSync('// edit\n');
      final plan = planFor(dir);
      expect(() => applyPlan(plan), throwsA(isA<DirtyTreeException>()));
      expect(applyPlan(plan, force: true).written, hasLength(2));
    });

    test('refuses outside a git repo unless forced', () {
      final dir = tempCopy('flat_provider');
      expect(() => applyPlan(planFor(dir)), throwsA(isA<DirtyTreeException>()));
    });

    test('skips files that changed since the preview', () {
      final dir = tempRepo('flat_provider');
      final plan = planFor(dir);
      final first = p.join(dir.path, plan.changes.first.path);
      File(first)
        ..createSync(recursive: true)
        ..writeAsStringSync('// sneaky\n');
      final result = applyPlan(plan, force: true);
      expect(result.stale, [plan.changes.first.path]);
      expect(result.written, [plan.changes.last.path]);
      expect(File(first).readAsStringSync(), '// sneaky\n');
    });
  });

  group('compiles', () {
    const apps = {
      'halp_style_app': ('nus_api.yaml', ['auth', 'user', 'cartridge', 'test']),
      'nus_style_app': ('nus_api.yaml', ['auth', 'user', 'cartridge', 'test']),
      'layered_http_app': ('shop.yaml', ['products', 'orders']),
    };
    for (final MapEntry(key: app, value: (specName, tags)) in apps.entries) {
      test(app, () {
        final dir = tempCopy(app);
        for (final tag in tags) {
          final out = ApiGenerator(
            ProjectContext.load(dir.path),
          ).generate(spec(specName), tag: tag);
          applyPlan(ChangePlan.build(dir.path, out.files), force: true);
        }
        // Offline when the pub cache has the packages (fast), else fetch.
        var get = Process.runSync('dart', [
          'pub',
          'get',
          '--offline',
        ], workingDirectory: dir.path);
        if (get.exitCode != 0) {
          get = Process.runSync('dart', [
            'pub',
            'get',
          ], workingDirectory: dir.path);
        }
        expect(get.exitCode, 0, reason: '${get.stdout}${get.stderr}');
        final analyze = Process.runSync('dart', [
          'analyze',
          '--fatal-infos',
        ], workingDirectory: dir.path);
        expect(analyze.exitCode, 0, reason: '${analyze.stdout}');
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  });
}
