# FlutterForge

AI coding agents write Flutter code that ignores how your project is built: the wrong state
management, extra layers, the wrong folder layout, a second HTTP client. FlutterForge reads your
project, works out its conventions, and hands them to the agent over MCP. It also turns an OpenAPI
spec into models and repositories written the way your project already writes them.

Everything is deterministic: there is no AI in the toolchain, and nothing is written until you
apply a previewed plan.

## 60-second tour

```bash
dart pub global activate flutterforge    # installs `flutterforge` and `flutterforge_mcp`
cd path/to/your_app
flutterforge rules
```

```markdown
# Project conventions: halp

## State management
- Use ChangeNotifier classes exposed with Provider (`context.watch` / `context.read`).
  Do not add Riverpod, BLoC or GetX. Name the file `*_controller.dart`.

## Folder layout
- One folder per feature: `lib/features/<feature>/`, with all files directly inside.

## Networking
- Use Dio. Go through the existing client in `lib/core/api_client.dart`; do not create new
  HTTP client instances. Repositories take a `Dio` in their constructor (field `_dio`).

## Models
- Models are hand-written classes with `factory X.fromMap(Map<String, dynamic>)` and `toMap()`.
...
```

Then connect the MCP server (below) and ask your agent for a feature as usual. It reads these
rules and real example files before writing code.

## MCP server

After `dart pub global activate flutterforge`, `flutterforge_mcp` is on your PATH
(`~/.pub-cache/bin`).

**Claude Code** (run inside your Flutter project):

```bash
claude mcp add flutterforge -- flutterforge_mcp
```

**Cursor**: add to `.cursor/mcp.json`:

```json
{ "mcpServers": { "flutterforge": { "command": "flutterforge_mcp" } } }
```

For the fastest startup, compile a native binary from a checkout of this repository and point the
config at it:

```bash
dart compile exe packages/flutterforge/bin/flutterforge_mcp.dart -o ~/.local/bin/flutterforge_mcp
```

The server uses its working directory as the project; pass `--root <dir>` to override.

| Tool | Writes? | What it does |
|---|---|---|
| `get_project_context` | no | Conventions as JSON, each with value, confidence and evidence files |
| `get_agent_rules` | no | Markdown rules to follow (also resource `flutterforge://rules`) |
| `find_similar_code` | no | 1–2 real files of a kind (`repository`, `screen`, `state`, `model`, `widget`, `service`, `test`) to copy |
| `plan_api_generation` | no | OpenAPI spec + tag → plan id, file summary, warnings, unified diff |
| `apply_plan` | yes | Writes a plan: refuses a dirty git tree, never overwrites, skips files changed since the plan |

Keep `apply_plan` on "ask every time" in your agent's permission settings; the read-only tools
are safe to allow.

## CLI

```bash
flutterforge context [--json]       # detected conventions, with confidence and evidence
flutterforge rules [--write]        # agent rules; --write previews .flutterforge/AGENT_RULES.md
flutterforge init [--apply]         # pin detected values in .flutterforge.yaml
flutterforge api --spec openapi.yaml --tag products            # preview diff, writes nothing
flutterforge api --spec openapi.yaml --tag products --apply    # write
flutterforge api --spec openapi.yaml --tag products --out plan.json && flutterforge apply plan.json
```

Global option: `-C <dir>` for the project directory. Exit codes: 0 ok, 1 error, 2 conflicts,
3 dirty git tree.

### Overriding detection

`.flutterforge.yaml` wins over anything detected:

```yaml
version: 1
conventions:
  layout: flat-feature          # flat-feature | layered-feature | layer-first
  state: provider               # set-state | provider | riverpod | bloc | getx
  network: dio                  # dio | http | chopper | retrofit
  client: dio                   # dio | http | api_client (what repositories hold)
  models: hand-written          # freezed | json_serializable | hand-written
  json_methods: fromMap/toMap   # fromJson/toJson | fromMap/toMap
  repository: concrete          # concrete | interface+impl
  imports: package              # package | relative
paths:
  features: lib/features
  api_client: lib/core/api_client.dart
```

A value with no evidence stays `unknown`; it is never guessed.

## What the generator copies from your project

- **Where files go:** `lib/features/<tag>/` (flat), `domain/` + `data/` (layered), or your
  existing models and repositories folders (layer-first).
- **How HTTP is called:** whatever existing repositories hold: a `Dio`, an `http.Client`, or your
  own API client class (its method arguments and a singleton such as `ApiClient.instance` are read
  from the source). `{code, message, data}` envelopes are unwrapped once.
- **Code style:** `fromJson/toJson` or `fromMap/toMap`, concrete repository or interface + `Impl`,
  package or relative imports, your `formatter.page_width`, and syntax for your SDK's language
  version (e.g. null-aware map entries on Dart 3.8+).

Safety: nothing is written without `--apply` / `apply_plan`; a dirty git tree is refused (unless
`--force`); only `lib/` and `test/` are written; existing files are never overwritten (they are
reported as conflicts); a saved plan skips any file that changed after the preview.

Not covered yet: `oneOf`/`anyOf` (typed as `Object?`), multipart, header parameters,
freezed/json_serializable output (hand-written models are generated, with a warning), and
project-specific error wrappers around API calls.

## Repository layout

- `packages/flutterforge_core`: scanner, convention detection, config, similar-code lookup,
  OpenAPI loader/emitter, change plans. Pure Dart; no Flutter, MCP or AI imports.
- `packages/flutterforge`: the `flutterforge` CLI (`lib/cli.dart`) and the `flutterforge_mcp`
  stdio server (`lib/mcp_server.dart`, on `dart_mcp`). Both only call `flutterforge_core`.
- `test/fixtures`: sample projects, OpenAPI specs and golden outputs. After reviewing a change to
  generated code, refresh goldens with `UPDATE_GOLDENS=1 dart test` in `packages/flutterforge_core`.
- `docs/MVP_PLAN.md`: scope and plan.

## License

MIT. See [LICENSE](LICENSE).
