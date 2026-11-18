# Flutter Dialect: a 5-minute walkthrough

The output below comes from a small Provider app (`flat_shop`): one folder per feature,
ChangeNotifier controllers, a Dio-based `ApiClient`, hand-written models.

## 1. Install

```bash
dart pub global activate flutter_dialect
```

This installs two commands: `flutter_dialect` (CLI) and `flutter_dialect_mcp` (MCP server).

## 2. See what was detected

```bash
cd path/to/your_app
flutter_dialect context
```

Each convention comes with a confidence score and the files it was read from. Anything
without evidence is shown as `unknown`, never guessed.

## 3. Get the rules your agent should follow

```bash
flutter_dialect rules
```

```markdown
# Project conventions: flat_shop

## State management
- Use ChangeNotifier classes exposed with Provider (`context.watch` / `context.read`).
  Do not add Riverpod, BLoC or GetX. Name the file `*_controller.dart`.

## Folder layout
- One folder per feature: `lib/features/<feature>/`, with all files directly inside.
  No data/domain/presentation subfolders.

## Networking
- Use Dio. Go through the existing client in `lib/core/api_client.dart`; do not create new
  HTTP client instances. Repositories hold `ApiClient` (field `_api`).

## Models
- Models are hand-written classes with `factory X.fromJson(Map<String, dynamic>)` and
  `toJson()`. No code generation (no freezed / json_serializable).

## File naming
- Screens end in `_page.dart`; state classes end in `_controller.dart`; repositories end in
  `_repository.dart`; models live in `*_models.dart`.
...
```

Wrong guess? Pin it: `flutter_dialect init --apply` writes `.flutter_dialect.yaml`, and
anything you set there beats detection.

## 4. Connect your AI agent

Claude Code, from inside the app:

```bash
claude mcp add flutter_dialect -- flutter_dialect_mcp
```

Cursor (`.cursor/mcp.json`):

```json
{ "mcpServers": { "flutter_dialect": { "command": "flutter_dialect_mcp" } } }
```

Now ask for a feature as usual ("add a mood check-in screen backed by
`GET /api/v1/mood-checkins`"). The agent calls `get_agent_rules` and
`find_similar_code` before writing, so the new code lands in `lib/features/mood_checkin/`
with a `_controller.dart`, a `_page.dart` and a repository that takes your client, like the
rest of the app.

## 5. Generate API code from OpenAPI

Using [`shop.yaml`](shop.yaml) from this folder:

```bash
flutter_dialect api --spec shop.yaml --tag orders
```

```text
warning: updateOrderStatus (PUT /orders/{orderId}/status): header parameter "X-Request-Id"
  is not generated; pass it through your API client.
warning: getPayment (GET /orders/{orderId}/payment): oneOf is not supported;
  GetPaymentResponse is typed as Object?.
--- /dev/null
+++ b/lib/features/orders/orders_models.dart
...
create    lib/features/orders/orders_models.dart
create    lib/features/orders/orders_repository.dart

Nothing written. Re-run with --apply to write.
```

The repository uses this app's `ApiClient`, so it looks like the ones you already have:

```dart
class OrdersRepository {
  OrdersRepository(this._api);

  final ApiClient _api;

  /// `GET /orders`
  Future<List<Order>> listOrders() async {
    final response = await _api.get('/orders');
    return (response as List<dynamic>)
        .map((e) => Order.fromJson(e as Map<String, dynamic>))
        .toList();
  }
  // ...
}
```

Happy with the diff? Commit your work, then:

```bash
flutter_dialect api --spec shop.yaml --tag orders --apply
```

`--apply` refuses a dirty git tree, writes only under `lib/` and `test/`, and never
overwrites an existing file.
