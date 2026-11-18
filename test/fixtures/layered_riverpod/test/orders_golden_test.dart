import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

void main() => testWidgets('golden', (t) async {
  await expectLater(find.byType(Object), matchesGoldenFile('orders.png'));
});
