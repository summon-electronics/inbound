// search_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:inboundgenie/PoItemDetailsPage.dart';
import 'package:mysql1/mysql1.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'DatabaseConnection.dart';
import 'dart:convert';


class PoItem {
  final String purchaseOrderId; // primary id from purchase_orders
  final String poNumber;
  final String date;
  final String supplier;
  final String trackingNumber; // NEW

  PoItem({
    required this.purchaseOrderId,
    required this.poNumber,
    required this.date,
    required this.supplier,
    required this.trackingNumber,
  });

  DateTime get parsedDate {
    try {
      // Handle "20 Jun 2020" format
      if (date.contains(' ') && date.split(' ').length == 3) {
        final parts = date.split(' ');
        final monthName = parts[1];
        final month = _monthNameToNumberStatic(monthName);
        return DateTime(
          int.parse(parts[2]),
          month,
          int.parse(parts[0]),
        );
      }
      // Handle MM/dd/yyyy format
      else if (date.contains('/')) {
        final parts = date.split('/');
        return DateTime(
          int.parse(parts[2]),
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
      }
      // Handle yyyy-MM-dd format
      else if (date.contains('-')) {
        return DateTime.parse(date);
      }
      return DateTime.now();
    } catch (e) {
      return DateTime.now();
    }
  }

  static int _monthNameToNumberStatic(String monthName) {
    const months = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
      'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12
    };
    return months[monthName] ?? 1;
  }
}

class Vendor {
  final String id;
  final String name;
  Vendor({required this.id, required this.name});
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  bool _showSearchButton = true;
  bool _isLoading = false;
  int _selectedIndex = -1;
  String _sortColumn = 'po'; // 'date', 'supplier', 'po'
  bool _sortAscending = true;
  List<PoItem> _displayedPoItems = [];

  // supplier suggestion state
  List<Vendor> _vendorSuggestions = [];
  bool _showVendorSuggestions = false;

  // selected date pill (human readable), kept separate from text field
  String? _selectedDateDisplay;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _sortItems() {
    setState(() {
      _displayedPoItems.sort((a, b) {
        int compare;
        switch (_sortColumn) {
          case 'date':
            compare = a.parsedDate.compareTo(b.parsedDate);
            break;
          case 'supplier':
            compare = a.supplier.compareTo(b.supplier);
            break;
          case 'po':
          default:
            compare = a.poNumber.compareTo(b.poNumber);
            break;
        }
        return _sortAscending ? compare : -compare;
      });
    });
  }

  void _onSortTapped(String column) async {
    if (column == 'date') {
      DateTime? pickedDate = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime.now(),
        builder: (BuildContext context, Widget? child) {
          return Theme(
            data: Theme.of(context).copyWith(
              // Make the dialog background white
              dialogBackgroundColor: Colors.white,
              // Tune the header/selected colors so they still match your app
              colorScheme: ColorScheme.light(
                primary: const Color(0xFF0070C0), // header & selected day color
                onPrimary: Colors.white,           // selected day text color
                onSurface: Colors.black87,         // day numbers & text
              ),
              // Buttons (CANCEL / OK) color
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0070C0),
                ),
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
      );

      if (pickedDate != null) {
        final isoDate =
            "${pickedDate.year.toString().padLeft(4, '0')}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}";
        final humanReadable =
            "${pickedDate.day} ${_getMonthName(pickedDate.month)} ${pickedDate.year}";

        setState(() {
          _sortColumn = 'date';
          _sortAscending = true;
          _selectedDateDisplay = humanReadable;
          _showVendorSuggestions = false;
          _showSearchButton = false;
          _controller.clear();
        });

        await _fetchPoByDate(isoDate);
      }
    } else if (column == 'supplier') {
      setState(() {
        _sortColumn = 'supplier';
        _sortAscending = true;
        _selectedDateDisplay = null;
        _vendorSuggestions = [];
        _showVendorSuggestions = false;
        _controller.clear();
        _displayedPoItems = [];
        _selectedIndex = -1;
        _showSearchButton = false;
      });
    } else {
      setState(() {
        _sortColumn = column;
        _sortAscending = true;
        _selectedDateDisplay = null;
        _showVendorSuggestions = false;
        _controller.clear();
        _displayedPoItems = [];
        _selectedIndex = -1;
        _sortItems();
        _showSearchButton = true;
      });
    }
  }



  Future<void> _fetchPoByDate(String selectedDate) async {
    setState(() {
      _isLoading = true;
      _showSearchButton = false;
      _displayedPoItems.clear();
      _selectedIndex = -1;
    });

    try {
      final response = await http.get(
        Uri.parse(
          "https://jellyfish-app-qfsmg.ondigitalocean.app/purchase-orders/date/$selectedDate",
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] && data['purchaseOrders'] != null) {
          final poMap = <String, PoItem>{};

          for (final row in data['purchaseOrders']) {
            final poNumber = row['purchase_order_number']?.toString() ?? '';
            final poId = row['purchase_order_id']?.toString() ?? '';
            final tracking = row['tracking_number']?.toString() ?? '';

            if (poNumber.isNotEmpty && poId.isNotEmpty && !poMap.containsKey(poNumber)) {
              poMap[poNumber] = PoItem(
                purchaseOrderId: poId,
                poNumber: poNumber,
                date: row['created_date']?.toString() ?? 'N/A',
                supplier: row['vendor_id']?.toString() ?? 'N/A',
                trackingNumber: tracking,
              );
            }
          }

          setState(() {
            _displayedPoItems = poMap.values.toList();
            _sortItems();
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No results for $selectedDate')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${response.reasonPhrase}')),
        );
      }
    } catch (e, st) {
      debugPrint('Date filter error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }


  Future<void> _onSearch() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a PO or Tracking Number')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _displayedPoItems.clear();
      _selectedIndex = -1;
      _showVendorSuggestions = false;
    });

    try {
      final trimmedQuery = query.trim();
      debugPrint("query: ${trimmedQuery}");
      final response = await http.get(
        Uri.parse(
          "https://jellyfish-app-qfsmg.ondigitalocean.app/purchase-orders/search?q=$trimmedQuery",
        ),
      );

      debugPrint("response: ${response.statusCode}");
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("API Success Response: ${jsonEncode(data)}", wrapWidth: 1024);

        if (data['success'] == true && data['purchaseOrders'] != null && data['purchaseOrders'].isNotEmpty) {
          final poMap = <String, PoItem>{};

          for (final row in data['purchaseOrders']) {
            final poNumber = row['purchase_order_number']?.toString() ?? '';
            final poId = row['purchase_order_id']?.toString() ?? '';
            final tracking = row['tracking_number']?.toString() ?? '';

            if (poNumber.isNotEmpty && poId.isNotEmpty && !poMap.containsKey(poNumber)) {
              poMap[poNumber] = PoItem(
                purchaseOrderId: poId,
                poNumber: poNumber,
                date: row['created_date']?.toString() ?? 'N/A',
                supplier: row['vendor_id']?.toString() ?? 'N/A',
                trackingNumber: tracking,
              );
            }
          }

          setState(() {
            _displayedPoItems = poMap.values.toList();
            _sortItems();
          });
        } else {
          debugPrint("No results found in API");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'No results found')),
          );
        }
      } else {
        debugPrint("API Error Response: ${response.body}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${response.reasonPhrase}')),
        );
      }
    } catch (e) {
      debugPrint('Search error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }


  void _onSupplierTextChanged(String text) {
    // Reset displayed PO list until user selects vendor (optional)
    setState(() {
      _displayedPoItems = [];
      _selectedIndex = -1;
    });

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final query = text.trim();
      if (query.isEmpty) {
        setState(() {
          _vendorSuggestions = [];
          _showVendorSuggestions = false;
        });
        return;
      }
      _fetchVendorSuggestions(query);
    });
  }

  Future<void> _fetchVendorSuggestions(String query) async {
    try {
      final response = await http.get(
        Uri.parse("https://jellyfish-app-qfsmg.ondigitalocean.app/vendors?q=$query"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] && data['vendors'] != null) {
          final vendors = (data['vendors'] as List)
              .map((v) => Vendor(
            id: v['vendor_id'].toString(),
            name: v['vendor_name'].toString(),
          ))
              .toList();

          setState(() {
            _vendorSuggestions = vendors;
            _showVendorSuggestions = vendors.isNotEmpty;
          });
        } else {
          setState(() {
            _vendorSuggestions = [];
            _showVendorSuggestions = false;
          });
        }
      } else {
        setState(() {
          _vendorSuggestions = [];
          _showVendorSuggestions = false;
        });
      }
    } catch (e, st) {
      debugPrint('Vendor suggestion error: $e\n$st');
      setState(() {
        _vendorSuggestions = [];
        _showVendorSuggestions = false;
      });
    }
  }


  Future<void> _onSelectVendor(Vendor v) async {
    // Fill text field with chosen vendor name and hide suggestions
    _controller.text = v.name;
    setState(() {
      _showVendorSuggestions = false;
      _sortColumn = 'supplier';
      _selectedDateDisplay = null;
      _vendorSuggestions = [];
      _isLoading = true;
      _displayedPoItems = [];
      _selectedIndex = -1;
    });

    await _fetchPosByVendor(v.id);
  }


  Future<void> _fetchPosByVendor(String vendorId) async {
    setState(() => _isLoading = true);

    try {
      final response = await http.get(
        Uri.parse("https://jellyfish-app-qfsmg.ondigitalocean.app/po/$vendorId"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] && data['purchaseOrders'] != null) {
          final poMap = <String, PoItem>{};

          for (final row in data['purchaseOrders']) {
            final poNumber = row['purchase_order_number']?.toString() ?? '';
            final poId = row['purchase_order_id']?.toString() ?? '';
            final tracking = row['tracking_number']?.toString() ?? '';

            if (poNumber.isNotEmpty && poId.isNotEmpty && !poMap.containsKey(poNumber)) {
              poMap[poNumber] = PoItem(
                purchaseOrderId: poId,
                poNumber: poNumber,
                date: row['created_date']?.toString() ?? 'N/A',
                supplier: row['vendor_id']?.toString() ?? 'N/A',
                trackingNumber: tracking,
              );
            }
          }

          setState(() {
            _displayedPoItems = poMap.values.toList();
            _sortItems();
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No purchase orders found for this supplier')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${response.reasonPhrase}')),
        );
      }
    } catch (e, st) {
      debugPrint('fetchPosByVendor error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }


  // ---------------- end supplier logic ----------------

  /// Save selected PO & tracking number to SharedPreferences
  Future<void> _saveSelectedPoToPrefs(PoItem item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selectedPoNumber', item.poNumber);
      await prefs.setString('selectedTrackingNumber', item.trackingNumber);
      // optional: you can also store purchaseOrderId if needed:
      await prefs.setString('selectedPurchaseOrderId', item.purchaseOrderId);


    } catch (e) {
      debugPrint('Error saving to prefs: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save selection: ${e.toString()}')),
      );
    }
  }

  void _navigateToDetails(PoItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PoItemDetailsPage(
          purchaseOrderId: item.purchaseOrderId,
          purchaseOrderNumber: item.poNumber,
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  int _monthNameToNumber(String monthName) {
    const months = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
      'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12
    };
    return months[monthName] ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;
    final paddingH = width * 0.04;
    final fontSize = width * 0.045;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0070C0),
        title: const Text(
          'Search',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 28, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: paddingH),
                      child: Center(
                        child: Text(
                          'Enter your PO or tracking number below\nto begin the inspection process',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: height * 0.02),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: paddingH),
                      child: Row(
                        children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: _buildFilterButton('PO Date', 'date'),
                            ),
                          ),
                          SizedBox(width: width * 0.02),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: _buildFilterButton('Supplier', 'supplier'),
                            ),
                          ),
                          SizedBox(width: width * 0.02),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: _buildFilterButton('PO Number', 'po'),
                            ),
                          ),
                        ],
                      ),
                    ),




                    // optional date pill
                    const SizedBox(height: 8),
                    if (_selectedDateDisplay != null)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: paddingH),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE6F3FF),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFF0070C0)),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    _selectedDateDisplay!,
                                    style: const TextStyle(
                                      color: Color(0xFF0070C0),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedDateDisplay = null;
                                        _sortColumn = 'po';
                                        _displayedPoItems = [];
                                      });
                                    },
                                    child: const Icon(Icons.close, size: 18, color: Color(0xFF0070C0)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          TextField(
                            controller: _controller,
                            decoration: InputDecoration(
                              hintText: _sortColumn == 'supplier' ? 'Type supplier name' : 'Enter PO or Tracking Number',
                              // Use explicit borders so focused state shows blue
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Theme.of(context).dividerColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Theme.of(context).dividerColor, width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Color(0xFF0070C0), width: 2),
                              ),
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _isLoading
                                  ? SizedBox(
                                width: 24,
                                height: 24,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  // child: CircularProgressIndicator(
                                  //   strokeWidth: 2,
                                  //   color: const Color(0xFF0070C0),
                                  // ),
                                ),
                              )
                                  : null,
                            ),
                            textInputAction: TextInputAction.search,
                            onChanged: (text) {
                              if (_sortColumn == 'supplier') {
                                _onSupplierTextChanged(text);
                              }

                            },
                            onSubmitted: (_) {
                              if (_sortColumn == 'supplier') {
                                // if user pressed enter while typing supplier name -> attempt to fetch suggestions or fallback
                                if (_vendorSuggestions.isNotEmpty) {
                                  // do nothing — user should select suggestion
                                } else {
                                  _onSearch();
                                }
                              } else {
                                _onSearch();
                              }
                            },
                          ),

                          // suggestions box (shown only when supplier filter is active)
                          if (_sortColumn == 'supplier' && _showVendorSuggestions)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              constraints: BoxConstraints(maxHeight: height * 0.35),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: theme.dividerColor),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
                              ),
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: _vendorSuggestions.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, idx) {
                                  final v = _vendorSuggestions[idx];
                                  return ListTile(
                                    title: Text(v.name),
                                    subtitle: Text('ID: ${v.id}'),
                                    onTap: () => _onSelectVendor(v),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    if (_displayedPoItems.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text('PO Number',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('PO Date',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),

                    if (_isLoading)
                      Center(
                        child: Image.asset(
                          'assets/images/loading.gif',
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                        ),
                      )

                    else if (_displayedPoItems.isNotEmpty)
                      ListView.separated(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _displayedPoItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = _displayedPoItems[index];
                          final selected = index == _selectedIndex;
                          const lightBlue = Color(0xFFE6F3FF);         // normal item background
                          const lightBlueSelected = Color(0xFFD6EEF9); // selected item background
                          const blue = Color(0xFF0070C0);              // selected text color

                          return InkWell(
                            onTap: () {
                              setState(() => _selectedIndex = index);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: selected ? lightBlueSelected : lightBlue,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // Left column: PO Number and PO ID
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // PO Number (bold) — blue if selected, black otherwise
                                      Text(
                                        item.poNumber,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: selected ? blue : Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      // Purchase Order ID — blue if selected, black otherwise
                                      Text(
                                        'ID: ${item.purchaseOrderId}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: selected ? blue : Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      // Tracking number (smaller)
                                      Text(
                                        'Tracking: ${item.trackingNumber.isEmpty ? "(none)" : item.trackingNumber}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: selected ? blue : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),

                                  // Right: Date — blue if selected, black otherwise
                                  Text(
                                    item.date,
                                    style: TextStyle(
                                      color: selected ? blue : Colors.black,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    else if (!_isLoading)
                        Center(
                          child: Text(
                            'No results found',
                            style: TextStyle(color: theme.disabledColor),
                          ),
                        ),
                  ],
                ),
              ),
            ),
    Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
    children: [
    // Show SEARCH button only if results are not fetched yet
    if (_showSearchButton)
    SizedBox(
    width: double.infinity,
    height: 48,
    child: ElevatedButton(
    onPressed: () async {
    await _onSearch();
    setState(() {
    _showSearchButton = false; // Hide after search results
    });
    },
    style: ElevatedButton.styleFrom(
    backgroundColor: const Color(0xFF0070C0),
    shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
    ),
    ),
    child: const Text(
    'SEARCH',
    style: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    ),
    ),
    ),
    ),

    const SizedBox(height: 8),

    // Show SELECT button only when user selects an item
    if (_selectedIndex != -1)
    SizedBox(
    width: double.infinity,
    child: ElevatedButton(
    onPressed: () async {
    final item = _displayedPoItems[_selectedIndex];
    await _saveSelectedPoToPrefs(item);
    _navigateToDetails(item);
    },
    style: ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    side: const BorderSide(color: Color(0xFF0070C0)),
    shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
    ),
    padding: const EdgeInsets.symmetric(vertical: 14),
    ),
    child: const Text(
    'SELECT',
    style: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: Color(0xFF0070C0),
    ),
    ),
    ),
    ),
    ],
    ),
    ),

    ],
        ),
      ),
    );
  }

  Widget _buildFilterButton(String label, String columnKey) {
    final theme = Theme.of(context);
    final isActive = _sortColumn == columnKey;
    const blue = Color(0xFF0070C0);
    return OutlinedButton(
      onPressed: () => _onSortTapped(columnKey),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: isActive ? blue : theme.dividerColor,
          width: isActive ? 2 : 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        backgroundColor: isActive ? const Color(0xFFE6F3FF) : null, // light blue highlight
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isActive ? blue : Colors.black,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Icon(
            _sortColumn == columnKey
                ? (_sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down)
                : Icons.arrow_drop_down,
            color: isActive ? blue : theme.disabledColor,
          ),
        ],
      ),
    );
  }
}
