import 'package:shared_preferences/shared_preferences.dart';

/// The PO and canonical line-item ID that own every inspection record.
class InspectionSelection {
  final String purchaseOrderId;
  final String poNumber;
  final String itemId;

  InspectionSelection({
    required String purchaseOrderId,
    required String poNumber,
    required String itemId,
  }) : purchaseOrderId = purchaseOrderId.trim(),
       poNumber = poNumber.trim(),
       itemId = itemId.trim() {
    if (this.purchaseOrderId.isEmpty ||
        this.poNumber.isEmpty ||
        this.itemId.isEmpty ||
        this.itemId == 'null') {
      throw const FormatException(
        'Select a PO and an item with a valid item_id.',
      );
    }
  }

  static String itemKey(String poId) => 'selected_item_id:$poId';

  Future<void> persist(SharedPreferences prefs) async {
    // Keep the keys used by subsequent inspection pages in sync. Do not
    // navigate until every write succeeds.
    final writes = <String, String>{
      'selectedPurchaseOrderId': purchaseOrderId,
      'selectedPoNumber': poNumber,
      'selected_item_id': itemId,
      itemKey(purchaseOrderId): itemId,
    };
    for (final entry in writes.entries) {
      if (!await prefs.setString(entry.key, entry.value)) {
        throw StateError('Could not save inspection selection. Please retry.');
      }
    }
  }
}
