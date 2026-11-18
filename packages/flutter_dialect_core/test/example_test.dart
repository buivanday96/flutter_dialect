import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('example/main.dart runs and writes nothing', () {
    final app = p.normalize(
      p.join(
        Directory.current.path,
        '..',
        '..',
        'test',
        'fixtures',
        'halp_style_app',
      ),
    );
    final r = Process.runSync('dart', ['run', 'example/main.dart', app]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(r.stdout, contains('== halp_style'));
    expect(r.stdout, contains('# Project conventions: halp_style'));
    expect(
      r.stdout,
      contains('== Example repository: lib/features/home/home_repository.dart'),
    );
    expect(
      r.stdout,
      contains('create    lib/features/notes/notes_repository.dart'),
    );
    expect(r.stdout, contains('NotesRepository(this._dio)'));
    expect(
      Directory(p.join(app, 'lib', 'features', 'notes')).existsSync(),
      isFalse,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
