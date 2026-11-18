import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final fixtures = p.normalize(
  p.join(Directory.current.path, '..', '..', 'test', 'fixtures'),
);

/// Copy of a fixture under git, so apply_plan's safety checks are real.
Directory repoCopy(String name) {
  final dir = Directory.systemTemp.createTempSync('ff_mcp');
  final src = p.join(fixtures, name);
  for (final e in Directory(src).listSync(recursive: true)) {
    final target = p.join(dir.path, p.relative(e.path, from: src));
    if (e is Directory) Directory(target).createSync(recursive: true);
    if (e is File) {
      File(target).parent.createSync(recursive: true);
      e.copySync(target);
    }
  }
  // The spec lives inside the project, as it would for a real app.
  Directory(p.join(dir.path, 'api')).createSync();
  File(
    p.join(fixtures, 'specs', 'shop.yaml'),
  ).copySync(p.join(dir.path, 'api', 'shop.yaml'));
  for (final args in [
    ['init', '-q'],
    ['add', '-A'],
    ['-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'init'],
  ]) {
    Process.runSync('git', args, workingDirectory: dir.path);
  }
  return dir;
}

/// Starts the real server binary over stdio, like Claude Code does.
Future<(ServerConnection, Process)> start(String root) async {
  final process = await Process.start('dart', [
    'run',
    'bin/flutter_dialect_mcp.dart',
    '--root',
    root,
  ]);
  final client = MCPClient(Implementation(name: 'test', version: '0'));
  final server = client.connectServer(
    stdioChannel(input: process.stdout, output: process.stdin),
  );
  final init = await server.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  expect(init.serverInfo.name, 'flutter_dialect');
  expect(init.instructions, contains('get_agent_rules'));
  server.notifyInitialized();
  return (server, process);
}

String text(CallToolResult r) =>
    r.content.map((c) => (c as TextContent).text).join('\n---\n');

void main() {
  late Directory dir;
  late ServerConnection server;
  late Process process;

  setUpAll(() async {
    dir = repoCopy('flat_provider');
    (server, process) = await start(dir.path);
  });

  tearDownAll(() async {
    await server.shutdown();
    process.kill();
    await process.exitCode;
    dir.deleteSync(recursive: true);
  });

  Future<CallToolResult> call(String name, [Map<String, Object?>? args]) =>
      server.callTool(CallToolRequest(name: name, arguments: args));

  test('lists the five tools with read-only hints', () async {
    final tools = (await server.listTools(ListToolsRequest())).tools;
    expect(tools.map((t) => t.name), [
      'get_project_context',
      'get_agent_rules',
      'find_similar_code',
      'plan_api_generation',
      'apply_plan',
    ]);
    for (final t in tools) {
      expect(
        t.toolAnnotations?.readOnlyHint,
        t.name != 'apply_plan',
        reason: t.name,
      );
    }
  });

  test('get_project_context', () async {
    final r = await call('get_project_context');
    final json = jsonDecode(text(r)) as Map<String, Object?>;
    expect(json['name'], 'flat_shop');
    expect(((json['conventions'] as Map)['state'] as Map)['value'], 'provider');
  });

  test('get_agent_rules', () async {
    final r = await call('get_agent_rules');
    expect(text(r), startsWith('# Project conventions: flat_shop'));
    expect(text(r), contains('ChangeNotifier'));
  });

  test('find_similar_code', () async {
    var r = await call('find_similar_code', {
      'kind': 'ChangeNotifier controller',
    });
    expect(r.content, hasLength(2));
    expect(
      text(r),
      contains('class ProductsController extends ChangeNotifier'),
    );

    r = await call('find_similar_code', {'kind': 'repository', 'limit': 1});
    expect(
      text(r),
      startsWith('// lib/features/products/products_repository.dart'),
    );

    r = await call('find_similar_code', {'kind': 'banana'});
    expect(r.isError, isTrue);
    expect(text(r), contains('repository, state, screen'));
  });

  test('resources', () async {
    final list = await server.listResources(ListResourcesRequest());
    expect(list.resources.map((r) => r.uri), [
      'dialect://context',
      'dialect://rules',
    ]);
    final read = await server.readResource(
      ReadResourceRequest(uri: 'dialect://rules'),
    );
    expect(
      (read.contents.single as TextResourceContents).text,
      contains('ChangeNotifier'),
    );
  });

  test('plan then apply', () async {
    final plan = await call('plan_api_generation', {
      'spec': 'api/shop.yaml',
      'tag': 'orders',
    });
    expect(plan.isError, isNot(true));
    final body = text(plan);
    expect(body, startsWith('plan_id: plan-'));
    expect(body, contains('+++ b/lib/features/orders/orders_repository.dart'));
    final id = RegExp(r'plan_id: (\S+)').firstMatch(body)![1]!;
    expect(
      Directory(p.join(dir.path, 'lib/features/orders')).existsSync(),
      isFalse,
      reason: 'planning writes nothing',
    );

    final applied = await call('apply_plan', {'plan_id': id});
    expect(applied.isError, isNot(true), reason: text(applied));
    expect(
      text(applied),
      contains('wrote     lib/features/orders/orders_models.dart'),
    );

    // The plan is used up.
    final again = await call('apply_plan', {'plan_id': id});
    expect(again.isError, isTrue);

    // The tree is now dirty: a new plan is refused without force.
    final p2 = text(
      await call('plan_api_generation', {
        'spec': 'api/shop.yaml',
        'tag': 'orders',
      }),
    );
    final id2 = RegExp(r'plan_id: (\S+)').firstMatch(p2)![1]!;
    final dirty = await call('apply_plan', {'plan_id': id2});
    expect(dirty.isError, isTrue);
    expect(text(dirty), contains('uncommitted'));
  });

  test('errors are readable tool errors', () async {
    var r = await call('plan_api_generation', {
      'spec': 'api/missing.yaml',
      'tag': 'x',
    });
    expect(r.isError, isTrue);
    expect(text(r), contains('Spec not found'));
    r = await call('plan_api_generation', {
      'spec': 'api/shop.yaml',
      'tag': 'nope',
    });
    expect(r.isError, isTrue);
    expect(text(r), contains('Tags in the spec'));
  });
}
