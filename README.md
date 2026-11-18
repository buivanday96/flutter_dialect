# FlutterForge

Reads a Flutter project and works out its conventions (state management, folder layout,
HTTP client, model style, naming), then hands them to AI coding agents as short rules.
Deterministic: no AI in the toolchain, and nothing is written without `--apply`.

Status: Week 1 of the [MVP plan](docs/MVP_PLAN.md). The context engine and CLI work.
The OpenAPI generator (week 2) and the MCP server (week 3) are not built yet.

```bash
dart pub get
dart run forge_cli:flutterforge -C path/to/app context          # table
dart run forge_cli:flutterforge -C path/to/app context --json   # value + confidence + evidence
dart run forge_cli:flutterforge -C path/to/app rules            # markdown rules for agents
dart run forge_cli:flutterforge -C path/to/app rules --write    # preview .flutterforge/AGENT_RULES.md
dart run forge_cli:flutterforge -C path/to/app init --apply     # pin detected values in .flutterforge.yaml
```

Values in `.flutterforge.yaml` override detection. A value with no evidence stays `unknown`;
it is never guessed.

## Layout

- `packages/forge_core`: scanner, convention detection, config (pure Dart).
- `packages/forge_cli`: the `flutterforge` command.
- `test/fixtures`: sample projects the tests run against.
