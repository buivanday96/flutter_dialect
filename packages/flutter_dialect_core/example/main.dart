// Shows the flutter_dialect_core API on any Flutter project.
//
//   dart run example/main.dart path/to/your_flutter_app
//
// Nothing is written to the project: the API generation step only prints the
// plan (summary + diff).
import 'dart:io';

import 'package:flutter_dialect_core/flutter_dialect_core.dart';

/// A tiny OpenAPI spec, so the example works without one of your own.
const spec = '''
openapi: 3.0.3
info: {title: Notes, version: 1.0.0}
paths:
  /notes:
    get:
      operationId: listNotes
      tags: [notes]
      parameters:
        - {name: page, in: query, schema: {type: integer}}
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {type: array, items: {\$ref: '#/components/schemas/Note'}}
    post:
      operationId: createNote
      tags: [notes]
      requestBody:
        content:
          application/json:
            schema:
              type: object
              required: [text]
              properties:
                text: {type: string}
      responses:
        '201':
          description: created
          content:
            application/json:
              schema: {\$ref: '#/components/schemas/Note'}
components:
  schemas:
    Note:
      type: object
      required: [id, text]
      properties:
        id: {type: integer}
        text: {type: string}
        createdAt: {type: string, format: date-time}
''';

void main(List<String> args) {
  final root = args.isEmpty ? '.' : args.first;

  // 1. Detect the project's conventions.
  final ProjectContext ctx;
  try {
    ctx = ProjectContext.load(root);
  } on ScanException catch (e) {
    stderr.writeln('${e.message}\nUsage: dart run example/main.dart <app>');
    exitCode = 1;
    return;
  }
  print('== ${ctx.name}');
  ctx.conventions.forEach((key, d) {
    print(
      '  ${key.padRight(13)} ${d.value ?? 'unknown'}'
      '${d.isKnown ? '  (${d.confidence})' : ''}',
    );
  });

  // 2. The same conventions as rules for an AI agent.
  print('\n== Agent rules\n${ctx.toAgentRules()}');

  // 3. A real file to copy the style of.
  final examples = findSimilarCode(ProjectScanner().scan(root), 'repository');
  print(
    '== Example repository: '
    '${examples.isEmpty ? 'none found' : examples.first.path}',
  );

  // 4. OpenAPI → models + repository in this project's style (preview only).
  print('\n== API plan for tag "notes"');
  try {
    final generated = ApiGenerator(
      ctx,
    ).generate(OpenApiLoader().load(spec), tag: 'notes');
    final plan = ChangePlan.build(
      ctx.root,
      generated.files,
      warnings: generated.warnings,
    );
    print(plan.summary());
    for (final w in plan.warnings) {
      print('warning: $w');
    }
    print('\n${plan.diff()}');
    // To write the files: applyPlan(plan); it refuses a dirty git tree.
  } on GenerationException catch (e) {
    print('Cannot generate here: ${e.message}');
  }
}
