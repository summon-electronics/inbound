// WeightDimensionsPage.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:inboundgenie/PackageInteriorPage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'StepProgressBar.dart';

enum DimensionType { length, height, width }

class WeightDimensionsPage extends StatefulWidget {
  const WeightDimensionsPage({Key? key}) : super(key: key);
  @override
  State<WeightDimensionsPage> createState() => _WeightDimensionsPageState();
}

class _WeightDimensionsPageState extends State<WeightDimensionsPage> {
  // Firebase Storage instance
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Controllers
  final TextEditingController _weightCtrl = TextEditingController();
  final TextEditingController _lengthCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();
  final TextEditingController _widthCtrl = TextEditingController();

  // Image pickers
  final ImagePicker _picker = ImagePicker();
  File? _weightImage;
  File? _lengthImage;
  File? _heightImage;
  File? _widthImage;

  // Store upload status per image
  bool _isWeightUploading = false;
  bool _isLengthUploading = false;
  bool _isHeightUploading = false;
  bool _isWidthUploading = false;

  // Store download URLs for uploaded images
  String? _weightImageUrl;
  String? _lengthImageUrl;
  String? _heightImageUrl;
  String? _widthImageUrl;

  // Expected values
  static const int expectedWeight = 20;
  static const int expectedLength = 14;
  static const int expectedHeight = 8;
  static const int expectedWidth = 6;

  // Override flags
  bool _overrideWeight = false;
  bool _overrideDims = false;
  bool _isDamaged = false;

  // Firebase initialization
  Future<void> _ensureFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }

  // helper to produce safe path components
  String _safe(String s) => Uri.encodeComponent(s);

  // Guarded picker removed so user can pick another image while upload is running.
  Future<void> _pickImage(ImageSource source, DimensionType type) async {
    try {
      final XFile? file = await _picker.pickImage(source: source);
      if (file == null) return;
      if (!mounted) return;

      setState(() {
        switch (type) {
          case DimensionType.length:
            _lengthImage = File(file.path);
            _isLengthUploading = true;
            break;
          case DimensionType.height:
            _heightImage = File(file.path);
            _isHeightUploading = true;
            break;
          case DimensionType.width:
            _widthImage = File(file.path);
            _isWidthUploading = true;
            break;
        }
      });

      // upload and set URL (uploads run independently)
      switch (type) {
        case DimensionType.length:
          final url = await _uploadImageForType(File(file.path), 'length');
          if (url != null && mounted) setState(() => _lengthImageUrl = url);
          break;
        case DimensionType.height:
          final url = await _uploadImageForType(File(file.path), 'height');
          if (url != null && mounted) setState(() => _heightImageUrl = url);
          break;
        case DimensionType.width:
          final url = await _uploadImageForType(File(file.path), 'width');
          if (url != null && mounted) setState(() => _widthImageUrl = url);
          break;
      }
    } on PlatformException catch (e) {
      debugPrint('Image picker PlatformException: $e');
      // keep UI responsive; show friendly message if needed
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image picker error — try again.')),
      );
    } catch (e, st) {
      debugPrint('Unexpected picker error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unexpected error picking image')),
      );
    }
  }

  // Guarded picker specifically for weight image (keeps code clearer)
  Future<void> _pickWeightImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(source: source);
      if (file == null) return;
      if (!mounted) return;

      setState(() {
        _weightImage = File(file.path);
        _isWeightUploading = true;
      });

      final url = await _uploadImageForType(File(file.path), 'weight');
      if (url != null && mounted) setState(() => _weightImageUrl = url);
    } on PlatformException catch (e) {
      debugPrint('Weight picker PlatformException: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image picker error — try again.')),
      );
    } catch (e, st) {
      debugPrint('Unexpected weight picker error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unexpected error picking image')),
      );
    }
  }

  // Upload image to Firebase Storage and return download URL
  Future<String?> _uploadImageForType(File file, String type) async {
    await _ensureFirebase();

    try {
      final prefs = await SharedPreferences.getInstance();
      final poNumber = prefs.getString('selectedPoNumber') ?? '';
      final itemId = prefs.getString('selected_item_id') ?? '';

      if (poNumber.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No PO selected. Please select a PO first.')),
        );
        // reset uploading flag for the type
        _resetUploadingFlag(type);
        return null;
      }

      if (itemId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No item selected. Please select an item first.')),
        );
        _resetUploadingFlag(type);
        return null;
      }

      final ext = p.extension(file.path).replaceFirst('.', '').toLowerCase();
      final safePo = _safe(poNumber);
      final safeItem = _safe(itemId);

      final fileName = '$safeItem\_$type.$ext';
      final filePath = 'weight_dimensions/$safePo/$fileName';
      final ref = _storage.ref().child(filePath);
      final mime = _mimeTypeForExt(ext);

      final metadata = SettableMetadata(contentType: mime);
      final uploadTask = ref.putFile(file, metadata);

      // You can also add snapshot listeners here if you want percent progress
      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();

      // set appropriate URL/uploading flag
      setState(() {
        switch (type) {
          case 'weight':
            _weightImageUrl = url;
            _isWeightUploading = false;
            break;
          case 'length':
            _lengthImageUrl = url;
            _isLengthUploading = false;
            break;
          case 'height':
            _heightImageUrl = url;
            _isHeightUploading = false;
            break;
          case 'width':
            _widthImageUrl = url;
            _isWidthUploading = false;
            break;
        }
      });

      return url;
    } catch (e, st) {
      debugPrint('Error uploading $type image: $e\n$st');
      _resetUploadingFlag(type);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload $type image')));
      return null;
    }
  }

  void _resetUploadingFlag(String type) {
    setState(() {
      if (type == 'weight') _isWeightUploading = false;
      if (type == 'length') _isLengthUploading = false;
      if (type == 'height') _isHeightUploading = false;
      if (type == 'width') _isWidthUploading = false;
    });
  }

  String _mimeTypeForExt(String ext) {
    ext = ext.toLowerCase();
    if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
    if (ext == 'png') return 'image/png';
    if (ext == 'gif') return 'image/gif';
    if (ext == 'mp4' || ext == 'mov' || ext == 'avi' || ext == 'mkv') return 'video/mp4';
    return 'application/octet-stream';
  }

  // Save all data to Firestore (doc name weight_dimensions inside item-specific collection)
  Future<void> _saveToFirebase() async {
    await _ensureFirebase();

    // Basic validation
    if (!_overrideWeight && _weightCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter weight or override it')),
      );
      return;
    }
    if (!_overrideDims &&
        (_lengthCtrl.text.isEmpty || _heightCtrl.text.isEmpty || _widthCtrl.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter all dimensions or override them')),
      );
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final poNumber = prefs.getString('selectedPoNumber') ?? '';
      final itemId = prefs.getString('selected_item_id') ?? '';

      if (poNumber.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Purchase Order selected')),
        );
        return;
      }

      if (itemId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No item selected')),
        );
        return;
      }

      // Prepare data
      final data = {
        'weight': int.tryParse(_weightCtrl.text) ?? expectedWeight,
        'length': int.tryParse(_lengthCtrl.text) ?? expectedLength,
        'height': int.tryParse(_heightCtrl.text) ?? expectedHeight,
        'width': int.tryParse(_widthCtrl.text) ?? expectedWidth,
        'overrideWeight': _overrideWeight,
        'overrideDimensions': _overrideDims,
        'isDamaged': _isDamaged,
        'weightImageUrl': _weightImageUrl,
        'lengthImageUrl': _lengthImageUrl,
        'heightImageUrl': _heightImageUrl,
        'widthImageUrl': _widthImageUrl,
        'poNumber': poNumber,
        'itemId': itemId,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Save to Firestore under purchase order, inside item-specific collection, doc weight_dimensions
      await FirebaseFirestore.instance
          .collection('purchase_orders')
          .doc(poNumber)
          .collection('${itemId}_inspection')
          .doc('weight_dimensions')
          .set(data, SetOptions(merge: true));

      // Navigate after save
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PackageInteriorPage()),
      );
    } catch (e) {
      debugPrint('Error saving to Firestore: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _lengthCtrl.dispose();
    _heightCtrl.dispose();
    _widthCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Parse inputs
    final int? w = int.tryParse(_weightCtrl.text);
    final bool weightMismatch = w != null && w != expectedWeight;
    final int? l = int.tryParse(_lengthCtrl.text);
    final int? h = int.tryParse(_heightCtrl.text);
    final int? wd = int.tryParse(_widthCtrl.text);
    final bool dimsEntered =
        _lengthCtrl.text.isNotEmpty && _heightCtrl.text.isNotEmpty && _widthCtrl.text.isNotEmpty;
    final bool dimsMismatch =
        dimsEntered && (l != expectedLength || h != expectedHeight || wd != expectedWidth);

    // Main scaffold with white background
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0070C0),
        title: const Text(
          'WEIGHT & DIMENSIONS',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      // Column: scrollable content above, fixed bottom buttons below
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),

            StepProgressBar(
              currentStep: 2,
              totalSteps: 8,
              activeColor: const Color(0xFF0070C0),
              inactiveColor: Colors.grey.shade300,
              height: 4,
              spacing: 4,
            ),
            const SizedBox(height: 16),
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Weight Section
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Weight Input Card
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: TextField(
                              controller: _weightCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Weight (lbs)',
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                                suffixIcon: _isWeightUploading
                                    ? const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.0,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF0070C0),
                                    ),
                                  ),
                                )
                                    : IconButton(
                                  icon: const Icon(Icons.camera_alt),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => Dialog(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Text(
                                                'Pick Weight image',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              ListTile(
                                                leading: const Icon(
                                                  Icons.camera_alt,
                                                  color: Color(0xFF0070C0),
                                                ),
                                                title: const Text('Camera'),
                                                onTap: () async {
                                                  Navigator.pop(context);
                                                  await _pickWeightImage(ImageSource.camera);
                                                },
                                              ),
                                              ListTile(
                                                leading: const Icon(
                                                  Icons.photo_library,
                                                  color: Color(0xFF0070C0),
                                                ),
                                                title: const Text('Gallery'),
                                                onTap: () async {
                                                  Navigator.pop(context);
                                                  await _pickWeightImage(ImageSource.gallery);
                                                },
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: const Text(
                                                  'CANCEL',
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),

                        // Weight Image Preview
                        if (_weightImage != null) ...[
                          const SizedBox(height: 16),
                          Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            color: Colors.white,
                            child: Column(
                              children: [
                                Stack(
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => Dialog(
                                            child: Image.file(_weightImage!),
                                          ),
                                        );
                                      },
                                      child: ClipRRect(
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(12),
                                          topRight: Radius.circular(12),
                                        ),
                                        child: Image.file(
                                          _weightImage!,
                                          height: 150,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    if (_isWeightUploading)
                                      Container(
                                        height: 150,
                                        color: Colors.black54,
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            valueColor: AlwaysStoppedAnimation<Color>(
                                              Color(0xFF0070C0),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF0070C0),
                                    borderRadius: BorderRadius.only(
                                      bottomLeft: Radius.circular(12),
                                      bottomRight: Radius.circular(12),
                                    ),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'Weight Image',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Weight Warning
                        if (weightMismatch && !_overrideWeight) ...[
                          const SizedBox(height: 16),
                          Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            color: Colors.yellow.shade100,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Expected: $expectedWeight – You entered: ${_weightCtrl.text} ⚠️',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: _overrideWeight,
                                        onChanged: (v) {
                                          setState(() {
                                            _overrideWeight = v ?? false;
                                            if (_overrideWeight) {
                                              _weightCtrl.text = expectedWeight.toString();
                                            }
                                          });
                                        },
                                      ),
                                      const Expanded(
                                        child: Text('Override and set to expected'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Dimensions Section
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Length Card
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _lengthCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Length (in)',
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.white,
                                    suffixIcon: _isLengthUploading
                                        ? const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.0,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Color(0xFF0070C0),
                                        ),
                                      ),
                                    )
                                        : IconButton(
                                      icon: const Icon(Icons.camera_alt),
                                      onPressed: () => _showImageDialog(DimensionType.length),
                                    ),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                                if (_lengthImage != null) ...[
                                  const SizedBox(height: 12),
                                  Stack(
                                    children: [
                                      GestureDetector(
                                        onTap: () => _showImageDialog(DimensionType.length),
                                        child: Column(
                                          children: [
                                            Container(
                                              height: 100,
                                              decoration: BoxDecoration(
                                                color: Colors.grey[200],
                                                borderRadius: const BorderRadius.only(
                                                  topLeft: Radius.circular(8),
                                                  topRight: Radius.circular(8),
                                                ),
                                              ),
                                              child: Image.file(
                                                _lengthImage!,
                                                fit: BoxFit.cover,
                                                width: double.infinity,
                                              ),
                                            ),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.symmetric(
                                                vertical: 8,
                                              ),
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF0070C0),
                                                borderRadius: BorderRadius.only(
                                                  bottomLeft: Radius.circular(8),
                                                  bottomRight: Radius.circular(8),
                                                ),
                                              ),
                                              child: const Center(
                                                child: Text(
                                                  'Length Image',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_isLengthUploading)
                                        Container(
                                          height: 100,
                                          color: Colors.black54,
                                          child: const Center(
                                            child: CircularProgressIndicator(
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                Color(0xFF0070C0),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Height Card
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _heightCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Height (in)',
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.white,
                                    suffixIcon: _isHeightUploading
                                        ? const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.0,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Color(0xFF0070C0),
                                        ),
                                      ),
                                    )
                                        : IconButton(
                                      icon: const Icon(Icons.camera_alt),
                                      onPressed: () => _showImageDialog(DimensionType.height),
                                    ),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                                if (_heightImage != null) ...[
                                  const SizedBox(height: 12),
                                  Stack(
                                    children: [
                                      GestureDetector(
                                        onTap: () => _showImageDialog(DimensionType.height),
                                        child: Column(
                                          children: [
                                            Container(
                                              height: 100,
                                              decoration: BoxDecoration(
                                                color: Colors.grey[200],
                                                borderRadius: const BorderRadius.only(
                                                  topLeft: Radius.circular(8),
                                                  topRight: Radius.circular(8),
                                                ),
                                              ),
                                              child: Image.file(
                                                _heightImage!,
                                                fit: BoxFit.cover,
                                                width: double.infinity,
                                              ),
                                            ),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.symmetric(
                                                vertical: 8,
                                              ),
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF0070C0),
                                                borderRadius: BorderRadius.only(
                                                  bottomLeft: Radius.circular(8),
                                                  bottomRight: Radius.circular(8),
                                                ),
                                              ),
                                              child: const Center(
                                                child: Text(
                                                  'Height Image',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_isHeightUploading)
                                        Container(
                                          height: 100,
                                          color: Colors.black54,
                                          child: const Center(
                                            child: CircularProgressIndicator(
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                Color(0xFF0070C0),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Width Card
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _widthCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Width (in)',
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.white,
                                    suffixIcon: _isWidthUploading
                                        ? const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.0,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Color(0xFF0070C0),
                                        ),
                                      ),
                                    )
                                        : IconButton(
                                      icon: const Icon(Icons.camera_alt),
                                      onPressed: () => _showImageDialog(DimensionType.width),
                                    ),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                                if (_widthImage != null) ...[
                                  const SizedBox(height: 12),
                                  Stack(
                                    children: [
                                      GestureDetector(
                                        onTap: () => _showImageDialog(DimensionType.width),
                                        child: Column(
                                          children: [
                                            Container(
                                              height: 100,
                                              decoration: BoxDecoration(
                                                color: Colors.grey[200],
                                                borderRadius: const BorderRadius.only(
                                                  topLeft: Radius.circular(8),
                                                  topRight: Radius.circular(8),
                                                ),
                                              ),
                                              child: Image.file(
                                                _widthImage!,
                                                fit: BoxFit.cover,
                                                width: double.infinity,
                                              ),
                                            ),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.symmetric(
                                                vertical: 8,
                                              ),
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF0070C0),
                                                borderRadius: BorderRadius.only(
                                                  bottomLeft: Radius.circular(8),
                                                  bottomRight: Radius.circular(8),
                                                ),
                                              ),
                                              child: const Center(
                                                child: Text(
                                                  'Width Image',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_isWidthUploading)
                                        Container(
                                          height: 100,
                                          color: Colors.black54,
                                          child: const Center(
                                            child: CircularProgressIndicator(
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                Color(0xFF0070C0),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        // Dimensions Warning
                        if (dimsMismatch && !_overrideDims) ...[
                          const SizedBox(height: 16),
                          Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            color: Colors.yellow.shade100,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Expected: ${expectedLength}×${expectedHeight}×${expectedWidth} – '
                                        'You entered: ${_lengthCtrl.text}×${_heightCtrl.text}×${_widthCtrl.text} ⚠️',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: _overrideDims,
                                        onChanged: (v) {
                                          setState(() {
                                            _overrideDims = v ?? false;
                                            if (_overrideDims) {
                                              _lengthCtrl.text = expectedLength.toString();
                                              _heightCtrl.text = expectedHeight.toString();
                                              _widthCtrl.text = expectedWidth.toString();
                                            }
                                          });
                                        },
                                      ),
                                      const Expanded(
                                        child: Text('Override and set to expected'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Damaged toggle
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      color: Colors.white,
                      child: SwitchListTile(
                        title: const Text('Mark package as damaged'),
                        secondary: const Icon(
                          Icons.report_problem,
                          color: Color(0xFFFFDE21),
                        ),
                        value: _isDamaged,
                        onChanged: (val) {
                          setState(() => _isDamaged = val);
                          if (val) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PackageInteriorPage(),
                              ),
                            );
                          }
                        },
                      ),
                    ),

                    const SizedBox(height: 80), // give space so last content isn't hidden by bottom bar
                  ],
                ),
              ),
            ),

            // Fixed bottom buttons (Skip + Next Step)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF0070C0)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          backgroundColor: Colors.white,
                          elevation: 4,
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PackageInteriorPage(),
                          ),
                        ),
                        child: const Text(
                          'SKIP',
                          style: TextStyle(
                            color: Color(0xFF0070C0),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0070C0),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          elevation: 4,
                        ),
                        onPressed: () {
                          // NOTE: Mismatch warnings no longer block progression.
                          // We still keep checks for empty required fields (unless overridden).
                          _saveToFirebase();
                        },
                        child: const Text(
                          'NEXT STEP',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Show dialog for picking length/height/width images
  void _showImageDialog(DimensionType type) {
    String dimensionName;
    switch (type) {
      case DimensionType.length:
        dimensionName = 'Length';
        break;
      case DimensionType.height:
        dimensionName = 'Height';
        break;
      case DimensionType.width:
        dimensionName = 'Width';
        break;
    }

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Pick $dimensionName image',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF0070C0)),
                title: const Text('Camera'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickImage(ImageSource.camera, type);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: Color(0xFF0070C0),
                ),
                title: const Text('Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickImage(ImageSource.gallery, type);
                },
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'CANCEL',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
