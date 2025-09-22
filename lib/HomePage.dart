// lib/HomePage.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:inboundgenie/tracking_models.dart';
import 'LoginPage.dart';
import 'ScannerFlowPage.dart';
import 'SearchPage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _username;
  String? _email;
  String? _trackingNumber;
  TrackingInfo? _trackingInfo;
  bool _isLoading = false;
  String? _authError;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('user_name') ?? 'Unknown';
      _email = prefs.getString('user_email') ?? '';
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
  }

  // --- Carrier Detection ---
  String _determineCarrier(String trackingNumber) {
    // UPS tracking numbers start with "1Z" and are 18 characters
    if (trackingNumber.startsWith('1Z') && trackingNumber.length == 18) {
      return "UPS";
    }
    // FedEx tracking numbers are typically 12, 15, or 22 digits
    else if (RegExp(r'^\d{12}$').hasMatch(trackingNumber) ||
        RegExp(r'^\d{15}$').hasMatch(trackingNumber) ||
        RegExp(r'^\d{22}$').hasMatch(trackingNumber)) {
      return "FedEx";
    }
    // Default to FedEx if pattern not recognized
    return "FedEx";
  }

  // --- FedEx Integration ---
  static const _fedexTokenUrl = 'https://apis.fedex.com/oauth/token';
  static const _fedexClientId = 'l75e44685f7e2240148dfd24e7637f28ae';
  static const _fedexClientSecret = 'c5d58279ccc84f968673a843cf1384b9';

  Future<String> _getFedExToken() async {
    final body = 'grant_type=client_credentials'
        '&client_id=${Uri.encodeQueryComponent(_fedexClientId)}'
        '&client_secret=${Uri.encodeQueryComponent(_fedexClientSecret)}';

    final resp = await http.post(
      Uri.parse(_fedexTokenUrl),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Accept': 'application/json',
      },
      body: body,
    );

    if (resp.statusCode != 200) {
      throw Exception('FedEx OAuth failed: ${resp.statusCode} - ${resp.body}');
    }

    final data = jsonDecode(resp.body);
    final token = data['access_token'];
    if (token == null) {
      throw Exception('Missing access_token in FedEx response');
    }
    return token;
  }

  Future<void> fetchFedExTracking(String trackingNumber) async {
    setState(() {
      _isLoading = true;
      _trackingInfo = null;
      _authError = null;
      _trackingNumber = trackingNumber;
    });

    try {
      final token = await _getFedExToken();
      final resp = await http.post(
        Uri.parse('https://apis.fedex.com/track/v1/trackingnumbers'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'trackingInfo': [
            {
              'trackingNumberInfo': {'trackingNumber': trackingNumber}
            }
          ],
          'includeDetailedScans': true,
        }),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final info = TrackingInfo.fromFedExJson(trackingNumber, data);
        setState(() {
          _trackingInfo = info;
        });
      } else {
        final err = jsonDecode(resp.body);
        final msg = (err['errors'] is List && err['errors'].isNotEmpty)
            ? err['errors'][0]['message']
            : resp.body;
        setState(() {
          _authError = 'FedEx Tracking failed: $msg';
        });
      }
    } catch (e) {
      setState(() {
        _authError = 'FedEx Error: ${e.toString()}';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- UPS Integration ---
  static const _upsTokenUrl = 'https://wwwcie.ups.com/security/v1/oauth/token';
  static const _upsClientId = 'Ot1DVG948XXjIAYJ6GcXJAhp1JyVB1xXA6bjGAnODZ3A77Vb'; // Replace with your UPS client ID
  static const _upsClientSecret = 'gOnDcDCiH2IHHuskyNJdUW9KeRiVfYtPgcyvA0jF0IUCk5sQllDd6OcTlvg15YtA'; // Replace with your UPS client secret

  Future<String> _getUpsToken() async {
    // Use base64 encoding for UPS credentials
    final credentials = base64.encode(utf8.encode('$_upsClientId:$_upsClientSecret'));
    final resp = await http.post(
      Uri.parse(_upsTokenUrl),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': 'Basic $credentials',
      },
      body: {'grant_type': 'client_credentials'},
    );

    if (resp.statusCode != 200) {
      throw Exception('UPS OAuth failed: ${resp.statusCode} - ${resp.body}');
    }

    final data = jsonDecode(resp.body);
    final token = data['access_token'];
    if (token == null) {
      throw Exception('Missing access_token in UPS response');
    }
    return token;
  }

  Future<void> fetchUpsTracking(String trackingNumber) async {
    setState(() {
      _isLoading = true;
      _trackingInfo = null;
      _authError = null;
      _trackingNumber = trackingNumber;
    });

    try {
      final token = await _getUpsToken();
      final transId = 'TRANS_${DateTime.now().millisecondsSinceEpoch}';
      final resp = await http.get(
        Uri.parse('https://wwwcie.ups.com/api/track/v1/details/$trackingNumber'),
        headers: {
          'Authorization': 'Bearer $token',
          'transId': transId,
          'transactionSrc': 'InboundGenieApp',
          'Content-Type': 'application/json',
        },
      );

      // Debug print to see raw response
      print('UPS Response: ${resp.body}');

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final info = TrackingInfo.fromUpsJson(trackingNumber, data);
        setState(() {
          _trackingInfo = info;
        });
      } else {
        final err = jsonDecode(resp.body);
        final response = err['response'] ?? {};
        final errors = response['errors'] ?? [];
        final msg = errors.isNotEmpty
            ? errors[0]['message']
            : 'Unknown UPS error';
        setState(() {
          _authError = 'UPS Tracking failed (${resp.statusCode}): $msg';
        });
      }
    } catch (e) {
      setState(() {
        _authError = 'UPS Error: ${e.toString()}';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Unified tracking function
  Future<void> fetchTracking(String trackingNumber) async {
    final carrier = _determineCarrier(trackingNumber);
    if (carrier == "FedEx") {
      await fetchFedExTracking(trackingNumber);
    } else {
      await fetchUpsTracking(trackingNumber);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0070C0),
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, size: 28, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text(
          'Home',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        centerTitle: true,
      ),
      drawer: _buildDrawer(w, h),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: w * 0.06, vertical: h * 0.02),
          child: Column(
            children: [
              SizedBox(height: h * 0.05),
              Image.asset('assets/images/inspection_genie.png', width: w * 0.7),
              SizedBox(height: h * 0.05),
              if (_isLoading)
                const CircularProgressIndicator(color: Color(0xFF0070C0))
              else
                Center(
                  child: _trackingInfo != null
                      ? _buildSummaryCard(w, h)
                      : _buildScanCard(w, h),
                ),
              SizedBox(height: h * 0.05),
              Text(
                'If the QR Code is Unavailable\nPlease use Manual searching',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: w * 0.040,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
              SizedBox(height: h * 0.05),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanCard(double w, double h) {
    return Card(
      color: const Color(0xFFECEFF0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final code = await Navigator.of(context).push<String>(
            MaterialPageRoute(builder: (_) => const Scannerflowpage()),
          );
          if (code != null) {
            await fetchTracking(code);
          }
        },
        child: Container(
          width: w * 0.6,
          height: w * 0.8,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/qr_code.png', width: w * 0.3, height: w * 0.3),
              SizedBox(height: h * 0.04),
              Text('SCAN QR CODE',
                  style: TextStyle(fontSize: w * 0.05, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SearchPage()));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF0070C0)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Skip scan → Manual PO',
                    style: TextStyle(
                      color: const Color(0xFF0070C0),
                      fontSize: w * 0.04,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(double w, double h) {
    final info = _trackingInfo!;
    final blue = const Color(0xFF0070C0);
    final isCancelled = info.status.toLowerCase().contains('cancel');

    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      child: Container(
        width: w * 0.78,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
                    ),
                    child: Image.asset('assets/images/qr_code.png', width: 40, height: 40),
                  ),
                  const SizedBox(height: 10),
                  const Text('SCAN QR CODE',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tracking ${info.trackingNumber}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black)),
                        const SizedBox(height: 8),
                        if (info.weightValue != null && info.weightUnit != null)
                          Text('Weight ${info.weightValue} ${info.weightUnit}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Carrier: ${info.carrierCode}',
                                style: const TextStyle(fontSize: 13, color: Colors.black87),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Authentication error
            if (_authError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _authError!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isCancelled ? Colors.red.shade50 : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    isCancelled ? Icons.cancel : Icons.local_shipping,
                    color: isCancelled ? Colors.red : Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(info.status,
                          style: TextStyle(
                              color: isCancelled ? Colors.red : Colors.blue))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (info.events.isNotEmpty) ...[
              const Text('Tracking History',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Container(
                height: 150,
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8)),
                child: ListView.builder(
                  itemCount: info.events.length,
                  itemBuilder: (context, idx) {
                    final ev = info.events[idx];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.location_on, size: 20),
                      title: Text(ev.description,
                          style: const TextStyle(fontSize: 12)),
                      subtitle: Text('${ev.date} ${ev.time}\n${ev.location}',
                          style: const TextStyle(fontSize: 10)),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () {
                  // confirm action
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: blue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('CONFIRM',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SearchPage()));
              },
              child: Text('Skip scan → Manual PO',
                  style: TextStyle(color: blue, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(double w, double h) {
    return SizedBox(
      width: w * 0.6,
      child: Drawer(
        child: Container(
          color: const Color(0xFF0070C0),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: w * 0.04, vertical: h * 0.03),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_username ?? '',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(_email ?? '',
                          style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
                const Divider(color: Colors.white54),
                ListTile(
                  leading: const Icon(Icons.search, color: Colors.white),
                  title: const Text('START NEW\nINSPECTION',
                      style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context),
                ),
                const Divider(color: Colors.white54),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.white),
                  title: const Text('Logout', style: TextStyle(color: Colors.white)),
                  onTap: _logout,
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

