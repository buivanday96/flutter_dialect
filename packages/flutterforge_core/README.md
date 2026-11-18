# flutterforge_core

The engine behind [`flutterforge`](https://pub.dev/packages/flutterforge): pure Dart, no Flutter,
MCP or AI dependencies.

- `ProjectContext.load(root)`: detected conventions (state management, layout, HTTP client, model
  style, naming…), each with `value`, `confidence` and `evidence`; `.toAgentRules()` renders them
  as markdown for AI agents.
- `findSimilarCode(scan, kind)`: real example files of a kind to copy.
- `OpenApiLoader` + `ApiGenerator`: OpenAPI 3 → models and repository in the project's style.
- `ChangePlan` + `applyPlan`: preview as a unified diff, then write safely (git must be clean,
  only `lib/` and `test/`, never overwrites).

```dart
import 'package:flutterforge_core/flutterforge_core.dart';

void main() {
  final ctx = ProjectContext.load('path/to/app');
  print(ctx.toAgentRules());
}
```

Most people want the [`flutterforge`](https://pub.dev/packages/flutterforge) CLI and MCP server
instead.
