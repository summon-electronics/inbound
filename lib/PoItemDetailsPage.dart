import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:inboundgenie/HomePage.dart';
import 'package:inboundgenie/PackagePage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PoItemDetailsPage extends StatefulWidget {
  final String purchaseOrderId;
  final String purchaseOrderNumber;

  const PoItemDetailsPage({
    Key? key,
    required this.purchaseOrderId,
    required this.purchaseOrderNumber,
  }) : super(key: key);

  @override
  State<PoItemDetailsPage> createState() => _PoItemDetailsPageState();
}

class _PoItemDetailsPageState extends State<PoItemDetailsPage> {
  bool _isLoading = true;
  List<Map<String, String>> _items = [];
  String? _error;

  // Single-selection state (one radio selected at a time)
  late List<bool> selectedItems;

  static const String _prefsSelectedItemKey = 'selected_item_id';

  @override
  void initState() {
    super.initState();
    selectedItems = [];
    _fetchItems();
  }

  // Fetch PO items from API
  Future<void> _fetchItems() async {
    setState(() {
      _isLoading = true;
      _items = [];
      _error = null;
      selectedItems = [];
    });

    try {
      final url = Uri.parse(
        "https://jellyfish-app-qfsmg.ondigitalocean.app/purchase-orders/items/${widget.purchaseOrderId}",
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        // Check response format
        if (decoded is! Map || decoded['items'] == null) {
          throw Exception('Unexpected API response format');
        }

        final List<dynamic> data = decoded['items'];

        final list = <Map<String, String>>[];
        for (final r in data) {
          list.add({
            'id': r['id']?.toString() ?? '',
            'item_id': r['item_id']?.toString() ?? '',
            'name': r['item_name']?.toString() ?? '',
            'desc': r['item_description']?.toString() ?? '',
            'qty': r['quantity_received']?.toString() ?? '0',
            'status': r['inspection_status']?.toString() ?? '0',
          });
        }

        // Load stored selected item
        final prefs = await SharedPreferences.getInstance();
        final storedSelectedItemId = prefs.getString(_prefsSelectedItemKey);

        final sel = List<bool>.filled(list.length, false);
        if (storedSelectedItemId != null && storedSelectedItemId.isNotEmpty) {
          final preIndex = list.indexWhere((it) => it['item_id'] == storedSelectedItemId);
          if (preIndex != -1) sel[preIndex] = true;
        }

        setState(() {
          _items = list;
          selectedItems = sel;
        });
      } else {
        setState(() {
          _error = 'Failed to fetch items. Status Code: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Select a single item and save it
  Future<void> _onCardTap(int index) async {
    final itemId = _items[index]['item_id'] ?? '';
    setState(() {
      for (var i = 0; i < selectedItems.length; i++) {
        selectedItems[i] = (i == index);
      }
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsSelectedItemKey, itemId);
    } catch (e) {
      debugPrint('Error saving selected item: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0070C0),
        elevation: 0,
        title: const Text(
          'PO ITEM DETAILS',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // List area
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text('Error: $_error'))
                : _items.isEmpty
                ? const Center(child: Text('No items found for this PO'))
                : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final it = _items[index];
                final selected = selectedItems.length > index && selectedItems[index];

                final rawDesc = it['desc'] ?? '';
                final desc = rawDesc.trim().isNotEmpty ? rawDesc.trim() : 'No Description';

                final qtyStr = it['qty'] ?? '';

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Card(
                    elevation: 4,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _onCardTap(index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: const Color(0xFF0070C0),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    it['name'] ?? 'Unnamed item',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Color(0xFF003366),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    desc,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF005A9E),
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0070C0),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                qtyStr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom action buttons
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              children: [
                // START INSPECTION
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final selectedIndex = selectedItems.indexWhere((e) => e == true);
                      if (selectedIndex == -1) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please select at least one item to start inspection.'),
                          ),
                        );
                        return;
                      }

                      final prefs = await SharedPreferences.getInstance();
                      final selectedItemId = _items[selectedIndex]['item_id'] ?? '';
                      if (selectedItemId.isNotEmpty) {
                        await prefs.setString(_prefsSelectedItemKey, selectedItemId);
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PackagePage()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0070C0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('START INSPECTION'),
                  ),
                ),
                const SizedBox(height: 16),
                // HOME
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const HomePage()),
                            (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0070C0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('HOME'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
