> **Note (2026-11-18):** the project was renamed to **Flutter Dialect** (packages
> `flutter_dialect_core` and `flutter_dialect`). This plan keeps its original wording.

# FlutterForge — MVP Plan (2–3 weeks, solo)

> A small, deterministic Dart toolkit that **understands a Flutter project's conventions**
> and exposes them to AI coding agents via MCP, plus a convention-aware OpenAPI generator.
> This replaces the original 8-sprint plan. Anything not listed here is out of scope for MVP.

## 1. Why this exists (the one differentiator)

AI agents (Claude Code, Cursor) write Flutter code that ignores a project's style:
wrong state management, extra layers, wrong folder layout, wrong HTTP client.
Existing tools don't solve this:

| Need | Already covered by | FlutterForge does |
|---|---|---|
| analyze / test / pub / widget tree | official `dart mcp-server` | nothing — don't duplicate |
| Parse OpenAPI | `swagger_parser`, `openapi_generator` | reuse a parser, own only the output templates |
| Scaffolding | Mason, `very_good_cli` | nothing |
| Lints | `dart analyze`, `custom_lint` | nothing in MVP |
| **Project conventions for agents** | nobody | **core feature** |
| **API code that matches the project's style** | nobody | **second feature** |

## 2. Principles

1. **AI optional.** Every command is deterministic; no AI SDK in the codebase.
2. **Detect, don't impose.** Generated code follows the detected (or configured) convention. The default style is flat, not clean-architecture.
3. **Preview, then write.** Generate a change plan (a unified diff) first. Write only with `--apply`.
4. **Git is the safety net.** Refuse `--apply` on a dirty working tree unless `--force`. No custom rollback/transaction system.
5. **Small surface.** 3 packages, no Dashboard, no use-case/repository-interface layers inside FlutterForge itself.

## 3. Repository layout

```text
flutterforge/
├── pubspec.yaml              # Dart pub workspace (no Melos needed for 3 packages)
├── analysis_options.yaml
├── packages/
│   ├── forge_core/           # pure Dart: scanner, conventions, config, openapi gen, diff
│   │   └── lib/src/
│   │       ├── context/      # scanner.dart, conventions.dart, project_context.dart
│   │       ├── config/       # forge_config.dart (.flutterforge.yaml)
│   │       ├── openapi/      # loader.dart, ir.dart, type_mapper.dart, emitter.dart
│   │       ├── templates/    # flat/, layered/ (code_builder or string templates)
│   │       └── changes/      # change_plan.dart, diff.dart, apply.dart
│   ├── forge_cli/            # bin/flutterforge.dart — thin `args` wrapper
│   └── forge_mcp/            # bin/flutterforge_mcp.dart — stdio MCP server
└── test/fixtures/            # sample Flutter projects + OpenAPI specs + golden outputs
```

Rules: `forge_cli` and `forge_mcp` only call `forge_core`. `forge_core` has no Flutter, MCP or AI imports.
Concrete classes everywhere. Add an interface only where a test needs a fake (e.g. a `FileSystem` in-memory fake).

## 4. Feature 1 — Project Context Engine

### Detects (from pubspec.yaml, pubspec.lock, lib/ tree, imports)
- Project name, Dart/Flutter SDK constraints, platforms present
- **State management**: setState only / Provider+ChangeNotifier / Riverpod / BLoC / GetX (by deps + import counts)
- **Router**: go_router / auto_route / Navigator only
- **Network**: dio / http / chopper / retrofit
- **DI**: get_it / injectable / Provider / constructor-only
- **Folder layout**: `flat-feature` (lib/features/x/*.dart) / `layered-feature` (x/data, x/domain, x/presentation) / `layer-first` (lib/models, lib/screens…)
- **Model style**: freezed / json_serializable / hand-written fromJson
- **Naming**: file suffixes in use (`_screen.dart`, `_page.dart`, `_repository.dart`, `_notifier.dart`…)
- Test setup: mocktail / mockito, golden tests present

Each value has `value`, `confidence` (0–1) and `evidence` (file paths). Unknown stays unknown, never guessed.

### Config override — `.flutterforge.yaml`
```yaml
version: 1
conventions:
  layout: flat-feature
  state: provider
  network: dio
  models: hand-written
  repository: concrete        # concrete | interface+impl
paths:
  features: lib/features
```
Explicit config beats detection.

### Output: `ProjectContext.toJson()` and `ProjectContext.toAgentRules()`
`toAgentRules()` produces a short markdown rules block ("Use ChangeNotifier + Provider. One folder per feature, files directly inside. Repositories are concrete classes. Use Dio via lib/core/api_client.dart…") that agents can read.

## 5. Feature 2 — Convention-aware OpenAPI generator

- Parse with an existing package (`swagger_parser`'s parser or `openapi_spec`) behind a small internal IR:
  `ApiDoc`, `ApiOperation`, `ApiSchema`, `ApiField` — only what the emitter needs.
- MVP coverage: primitives, nested objects, arrays, enums, nullable/required, `$ref`, path/query/body params, a JSON response model per operation.
- Out of MVP: oneOf/anyOf/discriminators, multipart, auth flows (just pass headers through the existing client).
- Output per tag/feature, **following the detected template**:
  - `flat` template: `lib/features/<feature>/<feature>_models.dart`, `<feature>_repository.dart` (concrete, uses the project's existing API client if found)
  - `layered` template: same code split into data/domain folders + interface (only when the project already does this)
- Formatted with `dart_style`. Output must be byte-identical across runs (golden tests).

## 6. Change plan / apply

```text
generate → ChangePlan { creates[], modifies[] } → print unified diff
--apply  → check git clean → re-check file hashes since preview → write
```
- Never delete files. Never modify files outside `lib/` and `test/` of the target project.
- If a target file exists and differs, report a conflict and skip it (no merge in MVP).
- Plan can be saved as JSON (`--out plan.json`) and applied later (`flutterforge apply plan.json`).

## 7. CLI

```bash
flutterforge context            # print detected context (human)
flutterforge context --json     # machine-readable
flutterforge rules              # print agent rules markdown
flutterforge rules --write      # write .flutterforge/AGENT_RULES.md (preview first)
flutterforge init               # create .flutterforge.yaml from detected values
flutterforge api --spec openapi.yaml --tag products            # preview diff
flutterforge api --spec openapi.yaml --tag products --apply    # write
flutterforge apply plan.json
```
Exit codes: 0 ok, 1 error, 2 conflicts, 3 dirty git tree.

## 8. MCP server (stdio, 5 tools)

| Tool | Writes? | Purpose |
|---|---|---|
| `get_project_context` | no | JSON context + confidence + evidence |
| `get_agent_rules` | no | markdown conventions for the agent to follow |
| `find_similar_code` | no | given "repository" / "screen" / "notifier", return 1–2 existing example files so the agent copies the real style |
| `plan_api_generation` | no | spec + tag → ChangePlan id + diff |
| `apply_plan` | yes | applies a plan id; requires the host's approval prompt; refuses if files changed since the plan |

Resource: `flutterforge://context`. SDK: spike `mcp_dart` (or `dart_mcp`) on day 1 of week 3; pin the version that works with Claude Code and Cursor.

## 9. Timeline

| Week | Deliverable | Done when |
|---|---|---|
| 1 | Workspace + `forge_core` scanner + config + `context`/`rules`/`init` CLI | Correct context JSON for 4 fixtures: flat+Provider, layered+Riverpod, BLoC, plain setState. Tested against 2 real projects (halp_flutter2, nus) |
| 2 | OpenAPI IR + flat & layered templates + change plan/diff/apply + `api` CLI | Golden tests pass; generating from nus `.doc/api` style spec produces code that compiles (`dart analyze` clean) in a fixture app |
| 3 | MCP server with 5 tools + README + pub.dev `0.1.0` | Claude Code connected to the MCP server writes a new feature in halp_flutter2 that follows flat/Provider rules without being told |

## 10. Definition of done (MVP)
- `dart format` + `dart analyze` clean, tests green on macOS + Ubuntu CI (GitHub Actions)
- Golden fixture tests for every template
- Deterministic output (run twice → identical)
- No write without `--apply` / `apply_plan`
- README with a 60-second demo (GIF): `flutterforge rules` → agent uses it

## 11. Explicitly later (post-MVP, only if people use it)
Dashboard (Flutter desktop/web), Inspector rules, UI token → ThemeData generator, test generator,
AI adapters, Figma integration, Windows path hardening, 3-way merge on conflicts.

## 12. Instructions for the coding agent
- Build in the order of section 9; stop and report at the end of each week.
- Keep files small and flat; no use-case classes, no interface per class, no DTO/mapper layer.
- Write fixture/golden tests before templates.
- Don't add packages beyond: `args`, `yaml`, `path`, `analyzer` (only if regex/import scan isn't enough), `code_builder` (optional), `dart_style`, one OpenAPI parser, one MCP SDK, `test`.
- Commit per milestone on a branch; do not push without asking.
