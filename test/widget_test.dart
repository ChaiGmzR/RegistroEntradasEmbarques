// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:registro_entradas_embarques/features/scan/scan_screen.dart';
import 'package:registro_entradas_embarques/main.dart';

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const RegistroEmbarquesApp(enableStartupUpdateCheck: false),
    );

    expect(find.text('Registro Embarques'), findsOneWidget);
    expect(find.text('Iniciar Sesión'), findsOneWidget);
  });

  testWidgets('entrada no EBR directa cambia a captura por cantidad', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: EntryScanForm(embedded: true)),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, 'ABQ74229133');
    await tester.pump();

    expect(find.text('Cantidad'), findsWidgets);
    expect(find.text('Box ID'), findsNothing);
  });

  testWidgets('entrada EBR directa queda lista para capturar Box ID', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: EntryScanForm(embedded: true)),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, 'EEBR41039119');
    await tester.pump();

    final qrField = tester.widget<TextFormField>(
      find.byType(TextFormField).first,
    );
    expect(qrField.controller?.text, 'EBR41039119');
    expect(find.text('Box ID'), findsWidgets);
    expect(find.text('Cantidad'), findsNothing);
  });
}
