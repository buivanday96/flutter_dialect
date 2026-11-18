import 'dart:convert';
import 'dart:io';

import 'package:forge_cli/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final fixtures = p.normalize(
  p.join(Directory.current.path, '..', '..', 'test', 'fixtures'),
);

Future<(int, String, String)> cli(List<String> args) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await run(args, out: out, err: err);
  return (code, '$out', '$err');
}

/// Copies a fixture to a temp dir so write commands can't touch the repo.
Directory tempCopy(String name) {
  final dir = Directory.systemTemp.createTempSync('ff_cli');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final e in Directory(p.join(fixtures, name)).listSync(recursive: true)) {
    final target = p.join(
      dir.path,
      p.relative(e.path, from: p.join(fixtures, name)),
    );
    if (e is Directory) Directory(target).createSync(recursive: true);
    if (e is File) {
      File(target).parent.createSync(recursive: true);
      e.copySync(target);
    }
  }
  return dir;
}

void main() {
  test('context prints a table', () async {
    final (code, out, _) = await cli([
      '-C',
      p.join(fixtures, 'flat_provider'),
      'context',
    ]);
    expect(code, ExitCode.ok);
    expect(out, contains('flat_shop'));
    expect(out, matches(RegExp(r'state\s+provider')));
  });

  test('context --json is valid JSON', () async {
    final (code, out, _) = await cli([
      '-C',
      p.join(fixtures, 'layered_riverpod'),
      'context',
      '--json',
    ]);
    expect(code, ExitCode.ok);
    final json = jsonDecode(out) as Map<String, dynamic>;
    expect(
      (json['conventions'] as Map)['state'],
      containsPair('value', 'riverpod'),
    );
  });

  test('rules prints markdown', () async {
    final (code, out, _) = await cli([
      '-C',
      p.join(fixtures, 'flat_provider'),
      'rules',
    ]);
    expect(code, ExitCode.ok);
    expect(out, startsWith('# Project conventions: flat_shop'));
  });

  test('rules --write previews, --apply writes', () async {
    final dir = tempCopy('flat_provider');
    final target = File(p.join(dir.path, rulesPath));

    var (code, out, _) = await cli(['-C', dir.path, 'rules', '--write']);
    expect(code, ExitCode.ok);
    expect(out, contains('Would create $rulesPath'));
    expect(target.existsSync(), isFalse);

    (code, out, _) = await cli(['-C', dir.path, 'rules', '--write', '--apply']);
    expect(code, ExitCode.ok);
    expect(target.readAsStringSync(), contains('ChangeNotifier'));

    (code, out, _) = await cli(['-C', dir.path, 'rules', '--write']);
    expect(out, contains('up to date'));
  });

  test('init refuses to clobber, then config wins', () async {
    final dir = tempCopy('flat_provider');
    var (code, _, _) = await cli(['-C', dir.path, 'init', '--apply']);
    expect(code, ExitCode.ok);

    final cfg = File(p.join(dir.path, '.flutterforge.yaml'));
    // Hand-edited: differs from what init would generate now.
    cfg.writeAsStringSync(
      '# team choice\n'
      '${cfg.readAsStringSync().replaceFirst('state: provider', 'state: bloc')}',
    );
    String err;
    (code, _, err) = await cli(['-C', dir.path, 'init', '--apply']);
    expect(code, ExitCode.conflict);
    expect(err, contains('--force'));

    final (_, out, _) = await cli(['-C', dir.path, 'context', '--json']);
    final state =
        ((jsonDecode(out) as Map)['conventions'] as Map)['state'] as Map;
    expect(state['value'], 'bloc');
    expect(state['source'], 'config');
  });

  test('errors exit 1', () async {
    final (code, _, err) = await cli(['-C', '/nonexistent/x', 'context']);
    expect(code, ExitCode.error);
    expect(err, contains('pubspec.yaml'));
    expect((await cli(['bogus'])).$1, ExitCode.error);
    expect((await cli([])).$1, ExitCode.error);
  });
}
