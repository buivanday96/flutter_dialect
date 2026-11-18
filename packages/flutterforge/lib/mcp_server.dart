import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:flutterforge_core/flutterforge_core.dart';
import 'package:path/path.dart' as p;

const version = '0.1.0';

const _instructions = '''
FlutterForge knows this Flutter project's conventions (state management, folder
layout, HTTP client, model style, naming). Before writing or changing Dart code
here, call get_agent_rules and follow it. Before creating a new repository,
screen, state class or model, call find_similar_code and copy the style of the
example. For API code from an OpenAPI spec, use plan_api_generation, show the
diff to the user, then apply_plan.''';

final _json = const JsonEncoder.withIndent('  ');

/// The FlutterForge MCP server for the project at [root].
base class FlutterForgeServer extends MCPServer
    with ToolsSupport, ResourcesSupport {
  FlutterForgeServer(super.channel, {required String root})
    : root = p.normalize(p.absolute(root)),
      super.fromStreamChannel(
        implementation: Implementation(name: 'flutterforge', version: version),
        instructions: _instructions,
      ) {
    registerTool(contextTool, _guard(_context));
    registerTool(rulesTool, _guard(_rules));
    registerTool(similarTool, _guard(_similar));
    registerTool(planTool, _guard(_plan));
    registerTool(applyTool, _guard(_apply));
    addResource(
      Resource(
        uri: 'flutterforge://context',
        name: 'Project context',
        description: 'Detected conventions with confidence and evidence.',
        mimeType: 'application/json',
      ),
      (request) => ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: request.uri,
            mimeType: 'application/json',
            text: _json.convert(ProjectContext.load(this.root).toJson()),
          ),
        ],
      ),
    );
    addResource(
      Resource(
        uri: 'flutterforge://rules',
        name: 'Agent rules',
        description: 'Markdown conventions to follow in this project.',
        mimeType: 'text/markdown',
      ),
      (request) => ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: request.uri,
            mimeType: 'text/markdown',
            text: ProjectContext.load(this.root).toAgentRules(),
          ),
        ],
      ),
    );
  }

  /// Absolute project root.
  final String root;

  /// Plans made by [planTool], by id. Lives as long as the server process.
  final plans = <String, ChangePlan>{};
  var _nextPlan = 1;

  static final contextTool = Tool(
    name: 'get_project_context',
    description:
        "The project's detected conventions as JSON: each with value, "
        'confidence (0-1) and evidence (file paths). Unknown values are null.',
    inputSchema: Schema.object(),
    annotations: ToolAnnotations(readOnlyHint: true, title: 'Project context'),
  );

  static final rulesTool = Tool(
    name: 'get_agent_rules',
    description:
        'Markdown rules for writing code that matches this project: state '
        'management, folder layout, networking, models, naming. Read before '
        'writing Dart code.',
    inputSchema: Schema.object(),
    annotations: ToolAnnotations(readOnlyHint: true, title: 'Agent rules'),
  );

  static final similarTool = Tool(
    name: 'find_similar_code',
    description:
        'Returns 1-2 existing files of a kind (repository, screen, state, '
        'model, widget, service, test) so you can copy their real style. '
        'Free text like "ChangeNotifier controller" or "page" works.',
    inputSchema: Schema.object(
      properties: {
        'kind': Schema.string(
          description:
              'What you are about to write, e.g. repository, screen, state, '
              'model, widget, service, test.',
        ),
        'limit': Schema.int(description: 'How many examples (1-3, default 2).'),
      },
      required: ['kind'],
    ),
    annotations: ToolAnnotations(readOnlyHint: true, title: 'Find examples'),
  );

  static final planTool = Tool(
    name: 'plan_api_generation',
    description:
        'Generates models + repository for one OpenAPI tag in the project '
        'style, without writing anything. Returns a plan_id, a file summary, '
        'warnings and a unified diff. Show the diff to the user, then call '
        'apply_plan.',
    inputSchema: Schema.object(
      properties: {
        'spec': Schema.string(
          description: 'OpenAPI 3 file (YAML/JSON), relative to the project.',
        ),
        'tag': Schema.string(description: 'Operations with this tag.'),
      },
      required: ['spec', 'tag'],
    ),
    annotations: ToolAnnotations(readOnlyHint: true, title: 'Plan API code'),
  );

  static final applyTool = Tool(
    name: 'apply_plan',
    description:
        'Writes the files of a plan from plan_api_generation. Refuses a dirty '
        'git tree (unless force), never overwrites existing files, and skips '
        'any file that changed since the plan was made.',
    inputSchema: Schema.object(
      properties: {
        'plan_id': Schema.string(),
        'force': Schema.bool(
          description: 'Write even with uncommitted git changes.',
        ),
      },
      required: ['plan_id'],
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      readOnlyHint: false,
      idempotentHint: false,
      title: 'Write planned files',
    ),
  );

  /// Turns exceptions into tool errors the agent can read.
  FutureOr<CallToolResult> Function(CallToolRequest) _guard(
    CallToolResult Function(Map<String, Object?> args) handler,
  ) => (request) {
    try {
      return handler(request.arguments ?? const {});
    } on ScanException catch (e) {
      return _error(e.message);
    } on FormatException catch (e) {
      return _error(e.message);
    } on ArgumentError catch (e) {
      return _error('${e.message}');
    } on GenerationException catch (e) {
      return _error(e.message);
    } on DirtyTreeException catch (e) {
      return _error(e.message);
    }
  };

  static CallToolResult _text(String text) =>
      CallToolResult(content: [TextContent(text: text)]);

  static CallToolResult _error(String text) =>
      CallToolResult(content: [TextContent(text: text)], isError: true);

  CallToolResult _context(Map<String, Object?> args) =>
      _text(_json.convert(ProjectContext.load(root).toJson()));

  CallToolResult _rules(Map<String, Object?> args) =>
      _text(ProjectContext.load(root).toAgentRules());

  CallToolResult _similar(Map<String, Object?> args) {
    final raw = '${args['kind'] ?? ''}';
    final kind = normalizeKind(raw);
    if (kind == null) {
      return _error(
        'Unknown kind "$raw". Use one of: ${codeKinds.keys.join(', ')}.',
      );
    }
    final limit = switch (args['limit']) {
      final int n => n.clamp(1, 3),
      _ => 2,
    };
    final found = findSimilarCode(
      ProjectScanner().scan(root),
      kind,
      limit: limit,
    );
    if (found.isEmpty) {
      return _text('No existing $kind files found. Follow get_agent_rules.');
    }
    return CallToolResult(
      content: [
        for (final e in found)
          TextContent(
            text:
                '// ${e.path} (${e.lines} lines'
                '${e.truncated ? ', truncated' : ''})\n${e.content}',
          ),
      ],
    );
  }

  CallToolResult _plan(Map<String, Object?> args) {
    final specPath = p.normalize(p.join(root, '${args['spec']}'));
    final file = File(specPath);
    if (!file.existsSync()) return _error('Spec not found: $specPath');
    final ctx = ProjectContext.load(root);
    final generated = ApiGenerator(ctx).generate(
      OpenApiLoader().load(file.readAsStringSync()),
      tag: '${args['tag']}',
    );
    final plan = ChangePlan.build(
      root,
      generated.files,
      warnings: generated.warnings,
    );
    final id = 'plan-${_nextPlan++}';
    plans[id] = plan;
    final b = StringBuffer()
      ..writeln('plan_id: $id')
      ..writeln()
      ..writeln(plan.summary());
    if (plan.warnings.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Warnings:');
      for (final w in plan.warnings) {
        b.writeln('- $w');
      }
    }
    if (plan.hasConflicts) {
      b
        ..writeln()
        ..writeln(
          'Conflicting files already exist and will be skipped; nothing is '
          'merged.',
        );
    }
    b
      ..writeln()
      ..write(plan.diff());
    return _text(b.toString());
  }

  CallToolResult _apply(Map<String, Object?> args) {
    final id = '${args['plan_id']}';
    final plan = plans[id];
    if (plan == null) {
      return _error(
        'Unknown plan_id "$id". Plans live only as long as the server; call '
        'plan_api_generation again.',
      );
    }
    final result = applyPlan(plan, force: args['force'] == true);
    plans.remove(id);
    final lines = [
      for (final w in result.written) 'wrote     $w',
      for (final c in result.conflicts) 'conflict  $c (exists; skipped)',
      for (final s in result.stale)
        'changed   $s (changed since plan; skipped)',
    ];
    return CallToolResult(
      content: [
        TextContent(
          text: lines.isEmpty ? 'Nothing to write.' : lines.join('\n'),
        ),
      ],
      isError: result.written.isEmpty && !result.clean,
    );
  }
}
