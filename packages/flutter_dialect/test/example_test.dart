import 'dart:io';

import 'package:flutter_dialect/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Keeps example/example.md honest: what it shows must match real output.
void main() {
  final fixtures = p.normalize(
    p.join(Directory.current.path, '..', '..', 'test', 'fixtures'),
  );
  final app = p.join(fixtures, 'flat_provider');
  final example = File('example/example.md').readAsStringSync();

  Future<String> cli(List<String> args) async {
    final out = StringBuffer();
    await run(args, out: out, err: StringBuffer());
    return '$out';
  }

  test('example spec is the fixture spec', () {
    expect(
      File('example/shop.yaml').readAsStringSync(),
      File(p.join(fixtures, 'specs', 'shop.yaml')).readAsStringSync(),
    );
  });

  test('rules shown in the example are real', () async {
    final rules = await cli(['-C', app, 'rules']);
    for (final line in [
      'Name the file `*_controller.dart`.',
      'Repositories hold `ApiClient` (field `_api`).',
      'Screens end in `_page.dart`; state classes end in `_controller.dart`',
    ]) {
      expect(rules, contains(line));
      expect(example.replaceAll(RegExp(r'\n\s*'), ' '), contains(line));
    }
  });

  test('repository shown in the example is real', () async {
    final diff = await cli([
      '-C',
      app,
      'api',
      '--spec',
      'example/shop.yaml',
      '--tag',
      'orders',
    ]);
    for (final line in [
      'OrdersRepository(this._api);',
      'final ApiClient _api;',
      "final response = await _api.get('/orders');",
      '.map((e) => Order.fromJson(e as Map<String, dynamic>))',
    ]) {
      expect(diff, contains(line));
      expect(example, contains(line));
    }
  });
}
