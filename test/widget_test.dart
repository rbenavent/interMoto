import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermoto/main.dart';

void main() {
  testWidgets('App arranca sin errores', (WidgetTester tester) async {
    await tester.pumpWidget(const InterMotoApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
