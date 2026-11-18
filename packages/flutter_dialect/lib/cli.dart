import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_dialect_core/flutter_dialect_core.dart';
import 'package:path/path.dart' as p;

/// Exit codes (see docs/MVP_PLAN.md §7).
abstract final class ExitCode {
  static const ok = 0;
  static const error = 1;
  static const conflict = 2;
  static const dirtyTree = 3;
}

const rulesPath = '.flutter_dialect/AGENT_RULES.md';

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
  parser.addCommand(
    'api',
    ArgParser()
      ..addOption(
        'spec',
        help: 'OpenAPI 3 file (YAML or JSON).',
        mandatory: true,
      )
      ..addOption(
        'tag',
        help: 'Generate the operations with this tag.',
        mandatory: true,
      )
      ..addOption('out', help: 'Also save the plan as JSON for `apply`.')
      ..addFlag('apply', negatable: false, help: 'Write the files.')
      ..addFlag('force', negatable: false, help: 'Write even if git is dirty.'),
  );
  parser.addCommand(
    'apply',
    ArgParser()
      ..addFlag('force', negatable: false, help: 'Write even if git is dirty.'),
  );
  return parser;
}

String usage(ArgParser parser) =>
    '''
Usage: flutter_dialect [-C <dir>] <command>

Commands:
  context [--json]          Print the detected project conventions.
  rules [--write [--apply]] Print agent rules; --write previews $rulesPath.
  init [--apply] [--force]  Create ${DialectConfig.fileName} from detected values.
  api --spec <file> --tag <tag> [--out plan.json] [--apply] [--force]
                            Preview (or write) models + repository for a tag.
  apply <plan.json> [--force]
                            Write a saved plan.

Exit codes: 0 ok, 1 error, 2 conflicts, 3 dirty git tree.

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

  if (command.name == 'apply') return _applySaved(command, out, err);

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
        DialectConfig.fileName,
        DialectConfig.fromContext(ctx).toYaml(),
        apply: command.flag('apply'),
        overwrite: command.flag('force'),
        out: out,
        err: err,
      );
    case 'api':
      return _api(ctx, command, out, err);
  }
  return ExitCode.error;
}

int _api(
  ProjectContext ctx,
  ArgResults command,
  StringSink out,
  StringSink err,
) {
  final specFile = File(command.option('spec')!);
  if (!specFile.existsSync()) {
    err.writeln('Spec not found: ${specFile.path}');
    return ExitCode.error;
  }
  final ChangePlan plan;
  try {
    final doc = OpenApiLoader().load(specFile.readAsStringSync());
    final generated = ApiGenerator(
      ctx,
    ).generate(doc, tag: command.option('tag')!);
    plan = ChangePlan.build(
      ctx.root,
      generated.files,
      warnings: generated.warnings,
    );
  } on FormatException catch (e) {
    err.writeln(e.message);
    return ExitCode.error;
  } on ArgumentError catch (e) {
    err.writeln(e.message);
    return ExitCode.error;
  } on GenerationException catch (e) {
    err.writeln(e.message);
    return ExitCode.error;
  }

  for (final w in plan.warnings) {
    err.writeln('warning: $w');
  }
  final outPath = command.option('out');
  if (outPath != null) {
    File(outPath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(plan.toJson())}\n',
    );
  }
  if (!command.flag('apply')) {
    out
      ..write(plan.diff())
      ..writeln()
      ..writeln(plan.summary())
      ..writeln()
      ..writeln(
        plan.hasWrites
            ? 'Nothing written. Re-run with --apply'
                  '${outPath != null ? ' or run `flutter_dialect apply $outPath`' : ''}'
                  ' to write.'
            : 'Nothing to write.',
      );
    return plan.hasConflicts ? ExitCode.conflict : ExitCode.ok;
  }
  return _applyPlan(plan, command.flag('force'), out, err);
}

int _applySaved(ArgResults command, StringSink out, StringSink err) {
  if (command.rest.length != 1) {
    err.writeln('Usage: flutter_dialect apply <plan.json> [--force]');
    return ExitCode.error;
  }
  final ChangePlan plan;
  try {
    final json = jsonDecode(File(command.rest.single).readAsStringSync());
    plan = ChangePlan.fromJson((json as Map).cast<String, Object?>());
  } on Object catch (e) {
    err.writeln('Could not read plan ${command.rest.single}: $e');
    return ExitCode.error;
  }
  return _applyPlan(plan, command.flag('force'), out, err);
}

int _applyPlan(ChangePlan plan, bool force, StringSink out, StringSink err) {
  final ApplyResult result;
  try {
    result = applyPlan(plan, force: force);
  } on DirtyTreeException catch (e) {
    err.writeln(e.message);
    return ExitCode.dirtyTree;
  }
  for (final path in result.written) {
    out.writeln('wrote     $path');
  }
  for (final path in result.conflicts) {
    err.writeln('conflict  $path (exists and differs; skipped)');
  }
  for (final path in result.stale) {
    err.writeln('changed   $path (changed since the preview; skipped)');
  }
  return result.clean ? ExitCode.ok : ExitCode.conflict;
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
  if (ctx.hasConfig) b.writeln('using ${DialectConfig.fileName}');
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
