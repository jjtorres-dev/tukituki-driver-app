import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:driver/app.dart';

void main() {
  testWidgets('TukiTuki Driver inicia correctamente', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TukiTukiDriverApp()));

    expect(find.text('TukiTuki'), findsOneWidget);
    expect(find.text('Conductor'), findsOneWidget);
  });
}
