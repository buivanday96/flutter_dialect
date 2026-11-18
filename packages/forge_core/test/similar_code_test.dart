import 'dart:io';

import 'package:forge_core/forge_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final fixtures = p.normalize(
  p.join(Directory.current.path, '..', '..', 'test', 'fixtures'),
);

ScanResult scan(String name) => ProjectScanner().scan(p.join(fixtures, name));

void main() {
  test('normalizeKind', () {
    expect(normalizeKind('repository'), 'repository');
    expect(normalizeKind('a ChangeNotifier controller'), 'state');
    expect(normalizeKind('view model'), 'state');
    expect(normalizeKind('Screen'), 'screen');
    expect(normalizeKind('pages'), 'screen');
    expect(normalizeKind('data models'), 'model');
    expect(normalizeKind('api client'), 'service');
    expect(normalizeKind('banana'), isNull);
  });

  test('repositories in a flat project', () {
    final found = findSimilarCode(scan('flat_provider'), 'repository');
    expect(found.single.path, 'lib/features/products/products_repository.dart');
    expect(found.single.content, contains('class ProductsRepository'));
  });

  test('picks from different folders first', () {
    final found = findSimilarCode(scan('flat_provider'), 'state');
    // Both qualify; the longer one is closer to ~100 lines, so it is first.
    expect(found.map((e) => e.path), [
      'lib/features/products/products_controller.dart',
      'lib/features/cart/cart_controller.dart',
    ]);
  });

  test('state holders by marker when names say nothing', () {
    final found = findSimilarCode(scan('bloc_layer_first'), 'state');
    expect(found.map((e) => e.path), [
      'lib/blocs/settings_bloc.dart',
      'lib/blocs/weather_cubit.dart',
    ]);
  });

  test('screens, tests, and nothing found', () {
    expect(
      findSimilarCode(scan('layered_riverpod'), 'screen').first.path,
      endsWith('_screen.dart'),
    );
    expect(findSimilarCode(scan('flat_provider'), 'test'), hasLength(1));
    expect(findSimilarCode(scan('plain_set_state'), 'repository'), isEmpty);
  });

  test('fakes rank last; view models are not models', () {
    final dir = Directory.systemTemp.createTempSync('ff_sim');
    addTearDown(() => dir.deleteSync(recursive: true));
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: s\n');
    void file(String path, String body) => File(p.join(dir.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(body);
    file(
      'lib/testing/fake_user_repository.dart',
      'class FakeUserRepository {}\n' * 100,
    );
    file('lib/http/user_repository.dart', 'class UserRepository {}\n' * 30);
    file('lib/screens/home_view_model.dart', 'class X {}\n' * 100);
    file('lib/model/user_model.dart', 'class U {}\n' * 20);
    final s = ProjectScanner().scan(dir.path);
    expect(
      findSimilarCode(s, 'repository').first.path,
      'lib/http/user_repository.dart',
    );
    expect(findSimilarCode(s, 'model').map((e) => e.path), [
      'lib/model/user_model.dart',
    ]);
  });

  test('long files are truncated', () {
    final found = findSimilarCode(scan('flat_provider'), 'screen', maxLines: 3);
    expect(found.first.truncated, isTrue);
    expect(found.first.content, endsWith('// … truncated'));
  });
}
