import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inboundgenie/inspection_selection.dart';
import 'package:inboundgenie/PoItemDetailsPage.dart';
import 'package:inboundgenie/PackagePage.dart';
import 'package:inboundgenie/WeightDimensionsPage.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('rejects incomplete IDs instead of opening an unowned inspection', () {
    expect(
      () => InspectionSelection(
        purchaseOrderId: 'PO1',
        poNumber: '123',
        itemId: '',
      ),
      throwsFormatException,
    );
    expect(
      () => InspectionSelection(
        purchaseOrderId: '',
        poNumber: '123',
        itemId: 'ITEM1',
      ),
      throwsFormatException,
    );
  });

  test(
    'keeps the whole PO/item context and scopes selection to a PO',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await InspectionSelection(
        purchaseOrderId: 'PO1',
        poNumber: '123',
        itemId: 'ITEM1',
      ).persist(prefs);
      await InspectionSelection(
        purchaseOrderId: 'PO2',
        poNumber: '456',
        itemId: 'ITEM2',
      ).persist(prefs);
      expect(prefs.getString('selectedPoNumber'), '456');
      expect(prefs.getString('selectedPurchaseOrderId'), 'PO2');
      expect(prefs.getString('selected_item_id'), 'ITEM2');
      expect(prefs.getString(InspectionSelection.itemKey('PO1')), 'ITEM1');
    },
  );

  MockClient itemsClient(Map<String, dynamic> row) => MockClient(
    (_) async => http.Response(
      jsonEncode({
        'items': [row],
      }),
      200,
    ),
  );

  testWidgets('persists route PO and item before opening package page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PoItemDetailsPage(
          purchaseOrderId: 'PO1',
          purchaseOrderNumber: '123',
          client: itemsClient({
            'id': 'ROW1',
            'item_id': 'ITEM1',
            'item_name': 'Part',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Part'));
    await tester.tap(find.text('START INSPECTION'));
    await tester.pumpAndSettle();
    final page = tester.widget<PackagePage>(find.byType(PackagePage));
    expect(page.selection.itemId, 'ITEM1');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('selectedPoNumber'), '123');
    expect(prefs.getString('selected_item_id'), 'ITEM1');
  });

  testWidgets('does not treat database row id as missing canonical item_id', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PoItemDetailsPage(
          purchaseOrderId: 'PO1',
          purchaseOrderNumber: '123',
          client: itemsClient({'id': 'ROW1', 'item_name': 'Part'}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Part'));
    await tester.tap(find.text('START INSPECTION'));
    await tester.pumpAndSettle();
    expect(find.byType(PackagePage), findsNothing);
    expect(find.textContaining('needs a valid item_id'), findsOneWidget);
  });

  testWidgets('SKIP saves an explicit skipped record then advances', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: PackagePage(
          selection: InspectionSelection(
            purchaseOrderId: 'PO1',
            poNumber: '123',
            itemId: 'ITEM1',
          ),
          saveMetadata: (data) async {
            saved = data;
          },
        ),
      ),
    );
    await tester.tap(find.text('SKIP'));
    await tester.pumpAndSettle();
    expect(saved?['skipped'], true);
    expect(saved?['itemId'], 'ITEM1');
    expect(find.byType(WeightDimensionsPage), findsOneWidget);
  });

  testWidgets('failed save keeps the inspector on the package page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PackagePage(
          selection: InspectionSelection(
            purchaseOrderId: 'PO1',
            poNumber: '123',
            itemId: 'ITEM1',
          ),
          saveMetadata: (_) async => throw StateError('test save failed'),
        ),
      ),
    );
    await tester.tap(find.text('SKIP'));
    await tester.pumpAndSettle();
    expect(find.byType(WeightDimensionsPage), findsNothing);
    expect(find.textContaining('Failed to save'), findsOneWidget);
  });

  testWidgets('NEXT still requires media; SKIP is the deliberate bypass', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PackagePage(
          selection: InspectionSelection(
            purchaseOrderId: 'PO1',
            poNumber: '123',
            itemId: 'ITEM1',
          ),
          saveMetadata: (_) async {},
        ),
      ),
    );
    await tester.tap(find.text('NEXT STEP'));
    await tester.pumpAndSettle();
    expect(find.byType(WeightDimensionsPage), findsNothing);
    expect(find.textContaining('Please capture all 6 images'), findsOneWidget);
  });

  testWidgets('unknown expectations do not compare against fake dimensions', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: WeightDimensionsPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('No verified expected dimensions'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(Checkbox), findsNothing);
  });
  testWidgets(
    'dimension override stays visible and can restore measured values',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: WeightDimensionsPage(
            expectedWeight: 20,
            expectedLength: 14,
            expectedHeight: 8,
            expectedWidth: 6,
          ),
        ),
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '20');
      await tester.enterText(fields.at(1), '10');
      await tester.enterText(fields.at(2), '10');
      await tester.enterText(fields.at(3), '5');
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byType(Checkbox),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(find.byType(Checkbox), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, true);
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, '14.0');
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, '10');
      expect(tester.widget<TextField>(fields.at(2)).controller!.text, '10');
      expect(tester.widget<TextField>(fields.at(3)).controller!.text, '5');
    },
  );
}
