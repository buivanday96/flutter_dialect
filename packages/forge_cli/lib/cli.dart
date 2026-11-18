import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:forge_core/forge_core.dart';
import 'package:path/path.dart' as p;

/// Exit codes (see docs/MVP_PLAN.md §7).
abstract final class ExitCode {
  static const ok = 0;
  static const error = 1;
  static const conflict = 2;
}

const rulesPath = '.flutterforge/AGENT_RULES.md';

ArgParser buildParser() {
  final parser = ArgParser()
    ..addOption(
      'path',
      abbr: 'C',
      help: 'Flutter project directory.',
      defaultsTo: '.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  parser.addCommand('context', ArgParser()..addFlag('json', negatable: false));
  parser.addCommand(
    'rules',
    ArgParser()
      ..addFlag('write', negatable: false, help: 'Preview writing $rulesPath.')
      ..addFlag('apply', negatable: false, help: 'Actually write the file.'),
  );
  parser.addCommand(
    'init',
    ArgParser()
      ..addFlag('apply', negatable: false, help: 'Actually write the file.')
      ..addFlag('force', negatable: false, help: 'Overwrite an existing file.'),
  );
  return parser;
}

String usage(ArgParser parser) =>
    '''
Usage: flutterforge [-C <dir>] <command>

Commands:
  context [--json]          Print the detected project conventions.
  rules [--write [--apply]] Print agent rules; --write previews $rulesPath.
  init [--apply] [--force]  Create ${ForgeConfig.fileName} from detected values.

Options:
${parser.usage}''';

Future<int> run(List<String> args, {StringSink? out, StringSink? err}) async {
  out ??= stdout;
  err ??= stderr;
  final parser = buildParser();
  final ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    err.writeln('${e.message}\n\n${usage(parser)}');
    return ExitCode.error;
  }
  final command = results.command;
  if (results.flag('help') || command == null) {
    out.writeln(usage(parser));
    return command == null && !results.flag('help')
        ? ExitCode.error
        : ExitCode.ok;
  }

  final root = p.normalize(p.absolute(results.option('path')!));
  final ProjectContext ctx;
  try {
    ctx = ProjectContext.load(root);
  } on ScanException catch (e) {
    err.writeln(e.message);
    return ExitCode.error;
  } on FormatException catch (e) {
    err.writeln(e.message);
    return ExitCode.error;
  }

  switch (command.name) {
    case 'context':
      if (command.flag('json')) {
        out.writeln(const JsonEncoder.withIndent('  ').convert(ctx.toJson()));
      } else {
        out.write(formatContext(ctx));
      }
      return ExitCode.ok;
    case 'rules':
      final rules = ctx.toAgentRules();
      if (!command.flag('write')) {
        out.write(rules);
        return ExitCode.ok;
      }
      return _writeFile(
        root,
        rulesPath,
        rules,
        apply: command.flag('apply'),
        overwrite: true,
        out: out,
        err: err,
      );
    case 'init':
      return _writeFile(
        root,
        ForgeConfig.fileName,
        ForgeConfig.fromContext(ctx).toYaml(),
        apply: command.flag('apply'),
        overwrite: command.flag('force'),
        out: out,
        err: err,
      );
  }
  return ExitCode.error;
}

int _writeFile(
  String root,
  String relPath,
  String content, {
  required bool apply,
  required bool overwrite,
  required StringSink out,
  required StringSink err,
}) {
  final file = File(p.join(root, relPath));
  final exists = file.existsSync();
  if (exists && file.readAsStringSync() == content) {
    out.writeln('$relPath is up to date.');
    return ExitCode.ok;
  }
  if (exists && !overwrite) {
    err.writeln(
      '$relPath already exists and differs. Use --force to replace it.',
    );
    return ExitCode.conflict;
  }
  if (!apply) {
    out
      ..writeln('Would ${exists ? 'update' : 'create'} $relPath:')
      ..writeln()
      ..write(content)
      ..writeln()
      ..writeln('Nothing written. Re-run with --apply to write it.');
    return ExitCode.ok;
  }
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  out.writeln('${exists ? 'Updated' : 'Created'} $relPath');
  return ExitCode.ok;
}

String formatContext(ProjectContext ctx) {
  final b = StringBuffer();
  final sdk = [
    if (ctx.dartSdk != null) 'Dart ${ctx.dartSdk}',
    if (ctx.flutterSdk != null) 'Flutter ${ctx.flutterSdk}',
  ];
  b.writeln(
    '${ctx.name}'
    '${sdk.isEmpty ? '' : '  (${sdk.join(', ')})'}'
    '${ctx.platforms.isEmpty ? '' : '  [${ctx.platforms.join(', ')}]'}',
  );
  if (ctx.hasConfig) b.writeln('using ${ForgeConfig.fileName}');
  b.writeln();

  void row(String key, Detection d) {
    final value = (d.value ?? 'unknown').padRight(24);
    final conf = d.isKnown ? d.confidence.toStringAsFixed(2) : '   -';
    final tag = d.source == 'config' ? ' (config)' : '';
    final ev = d.source == 'detected' && d.evidence.isNotEmpty
        ? '  ${d.evidence.take(2).join(', ')}'
              '${d.evidence.length > 2 ? ', …' : ''}'
        : '';
    b.writeln('  ${key.padRight(11)} $value $conf$tag$ev');
  }

  ctx.conventions.forEach(row);
  row('api client', ctx.apiClient);
  row('mocks', ctx.mocks);
  b
    ..writeln()
    ..writeln('  features    ${ctx.featuresPath ?? '-'}')
    ..writeln(
      '  naming      ${ctx.naming.isEmpty ? '-' : ctx.naming.entries.take(8).map((e) => '${e.key} ${e.value}').join(', ')}',
    )
    ..writeln(
      '  tests       ${ctx.testFileCount} files'
      '${ctx.goldens ? ', golden tests' : ''}',
    );
  return b.toString();
}
