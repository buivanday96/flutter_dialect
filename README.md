# FlutterForge

Reads a Flutter project and works out its conventions (state management, folder layout,
HTTP client, model style, naming), then hands them to AI coding agents as short rules.
Deterministic: no AI in the toolchain, and nothing is written without `--apply`.

Status: weeks 1–2 of the [MVP plan](docs/MVP_PLAN.md): context engine, CLI and the
convention-aware OpenAPI generator. The MCP server (week 3) is not built yet.

```bash
dart pub get
dart run forge_cli:flutterforge -C path/to/app context          # table
dart run forge_cli:flutterforge -C path/to/app context --json   # value + confidence + evidence
dart run forge_cli:flutterforge -C path/to/app rules            # markdown rules for agents
dart run forge_cli:flutterforge -C path/to/app rules --write    # preview .flutterforge/AGENT_RULES.md
dart run forge_cli:flutterforge -C path/to/app init --apply     # pin detected values in .flutterforge.yaml

# OpenAPI 3 → models + repository for one tag, in the project's style
dart run forge_cli:flutterforge -C path/to/app api --spec openapi.yaml --tag products           # diff only
dart run forge_cli:flutterforge -C path/to/app api --spec openapi.yaml --tag products --apply   # write
dart run forge_cli:flutterforge -C path/to/app api --spec openapi.yaml --tag products --out plan.json
dart run forge_cli:flutterforge apply plan.json
```

Exit codes: 0 ok, 1 error, 2 conflicts, 3 dirty git tree.

## What the generator copies from your project

- **Where files go:** `lib/features/<tag>/` (flat), `domain/` + `data/` (layered), or your
  existing models and repositories folders (layer-first).
- **How HTTP is called:** whatever existing repositories hold: a `Dio`, an `http.Client`, or your
  own API client class (its method arguments and a singleton such as `ApiClient.instance` are read
  from the source). `{code, message, data}` envelopes are unwrapped once.
- **Code style:** `fromJson/toJson` or `fromMap/toMap`, concrete repository or interface + `Impl`,
  package or relative imports, your `formatter.page_width`, and syntax for your SDK's language
  version.

Safety: nothing is written without `--apply`; `--apply` refuses a dirty git tree (unless
`--force`); only `lib/` and `test/` are written; existing files are never overwritten (reported as
conflicts); a saved plan skips any file that changed after the preview.

Not covered yet: `oneOf`/`anyOf` (typed as `Object?`), multipart, header parameters, and
freezed/json_serializable output (hand-written models are generated, with a warning).

Values in `.flutterforge.yaml` override detection. A value with no evidence stays `unknown`;
it is never guessed.

## Layout

- `packages/forge_core`: scanner, convention detection, config, OpenAPI loader/emitter, change
  plans (pure Dart).
- `packages/forge_cli`: the `flutterforge` command.
- `test/fixtures`: sample projects, OpenAPI specs and golden outputs
  (`UPDATE_GOLDENS=1 dart test` in `packages/forge_core` to refresh them after review).
