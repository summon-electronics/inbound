// PackageInteriorPage.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'PackingSlipPage.dart';
import 'StepProgressBar.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_firestore/cloud_firestore.dart';

class PackageInteriorPage extends StatefulWidget {
  const PackageInteriorPage({super.key});
  @override
  State<PackageInteriorPage> createState() => _PackageInteriorPageState();
}

class _PackageInteriorPageState extends State<PackageInteriorPage> {
  final picker = ImagePicker();
  File? _interiorImage;
  String? _interiorImageUrl;
  bool _isInteriorUploading = false;
  String? _testReportAnswer;

  // Firebase storage instance
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<void> _ensureFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }

  String _safe(String s) => Uri.encodeComponent(s);

  String _mimeTypeForExt(String ext) {
    ext = ext.toLowerCase();
    if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
    if (ext == 'png') return 'image/png';
    if (ext == 'gif') return 'image/gif';
    return 'application/octet-stream';
  }

  void _showImagePickerDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'PICK INTERIOR IMAGE',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              _buildOptionTile(
                icon: Icons.camera_alt,
                text: 'CAMERA',
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUpload(ImageSource.camera);
                },
              ),
              const SizedBox(height: 12),
              _buildOptionTile(
                icon: Icons.photo_library,
                text: 'GALLERY',
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUpload(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'CANCEL',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF0070C0)),
      title: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      onTap: onTap,
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final XFile? file = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null) return;

    final f = File(file.path);
    setState(() {
      _interiorImage = f;
      _isInteriorUploading = true;
    });

    // Start upload immediately (does not block UI for other actions)
    await _uploadInteriorImage(f);
  }

  Future<void> _uploadInteriorImage(File file) async {
    await _ensureFirebase();

    try {
      final prefs = await SharedPreferences.getInstance();
      final poNumber = prefs.getString('selectedPoNumber') ?? '';
      final itemId = prefs.getString('selected_item_id') ?? '';

      if (poNumber.isEmpty) {
        setState(() => _isInteriorUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No PO selected. Please select a PO first.')),
        );
        return;
      }

      if (itemId.isEmpty) {
        setState(() => _isInteriorUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No item selected. Please select an item first.')),
        );
        return;
      }

      final ext = p.extension(file.path).replaceFirst('.', '').toLowerCase();
      final mime = _mimeTypeForExt(ext);

      final safePo = _safe(poNumber);
      final safeItem = _safe(itemId);
      // slot name in this page is "interior"
      final slotName = 'interior';

      final fileName = '${safeItem}_${slotName}.$ext';
      final filePath = 'package_interior/$safePo/$fileName'; // requested pattern
      final ref = _storage.ref().child(filePath);

      final metadata = SettableMetadata(contentType: mime);
      final uploadTask = ref.putFile(file, metadata);

      // Optionally show percent progress by listening to snapshotEvents
      uploadTask.snapshotEvents.listen((event) {
        // you can calculate percent = event.bytesTransferred / event.totalBytes
        // and setState to show UI if you want — omitted to keep code concise
      });

      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();

      setState(() {
        _interiorImageUrl = url;
        _isInteriorUploading = false;
      });

    } catch (e, st) {
      debugPrint('Error uploading interior image: $e\n$st');
      setState(() => _isInteriorUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to upload interior image')),
      );
    }
  }

  Future<void> _deleteRemoteInteriorImage() async {
    if (_interiorImageUrl == null || _interiorImageUrl!.isEmpty) return;
    await _ensureFirebase();
    try {
      await FirebaseStorage.instance.refFromURL(_interiorImageUrl!).delete();
    } catch (e) {
      debugPrint('Failed to delete remote interior image: $e');
    }
  }

  void _removeImage() async {
    // First delete remote if present
    if (_interiorImageUrl != null && _interiorImageUrl!.isNotEmpty) {
      await _deleteRemoteInteriorImage();
    }

    setState(() {
      _interiorImage = null;
      _interiorImageUrl = null;
      _isInteriorUploading = false;
    });
  }

  /// 🔹 Save data into Firestore (under item-specific collection, doc 'package_interior_images')
  Future<void> _saveToFirestore() async {
    await _ensureFirebase();

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

      final data = {
        'interiorImageUrl': _interiorImageUrl,
        'testReportAnswer': _testReportAnswer,
        'poNumber': poNumber,
        'itemId': itemId,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('purchase_orders')
          .doc(poNumber)
          .collection('${itemId}_inspection')
          .doc('package_interior')
          .set(data, SetOptions(merge: true));

      // Navigate after save
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PackingSlipPage()),
      );
    } catch (e) {
      debugPrint('Error saving to Firestore: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0070C0),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'PACKAGE INTERIOR INSPECTION',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Progress bar for step 4 of 8
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: StepProgressBar(
              currentStep: 4,
              totalSteps: 8,
              activeColor: const Color(0xFF0070C0),
              inactiveColor: Colors.grey.shade300,
              height: 4,
              spacing: 4,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'IMAGE OF THE INTERIOR, BEFORE PRODUCTS ARE REMOVED',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: _showImagePickerDialog,
                          child: Container(
                            height: 200,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white, // White background
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12),
                              ),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (_interiorImage != null)
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(12),
                                    ),
                                    child: Image.file(
                                      _interiorImage!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                else
                                  const Center(
                                    child: Icon(
                                      Icons.add_a_photo,
                                      size: 48,
                                      color: Colors.grey,
                                    ),
                                  ),
                                if (_interiorImage != null)
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: GestureDetector(
                                      onTap: _removeImage,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (_isInteriorUploading)
                                  const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: const BoxDecoration(
                            color: Color(0xFF0070C0),
                            borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'ADD INTERIOR IMAGE',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'DOES THIS PACKAGE CONTAIN TEST REPORTS?',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 15),
                  Card(
                    color: Colors.white,
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          RadioListTile<String>(
                            title: const Text(
                              'YES',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            value: 'YES',
                            groupValue: _testReportAnswer,
                            onChanged: (value) =>
                                setState(() => _testReportAnswer = value),
                            activeColor: const Color(0xFF0070C0),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                          const Divider(),
                          RadioListTile<String>(
                            title: const Text(
                              'NO',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            value: 'NO',
                            groupValue: _testReportAnswer,
                            onChanged: (value) =>
                                setState(() => _testReportAnswer = value),
                            activeColor: const Color(0xFF0070C0),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      side: const BorderSide(
                        color: Color(0xFF0070C0),
                        width: 2,
                      ),
                    ),
                    onPressed: () {
                      // If skip, you can also save empty values if you want
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PackingSlipPage(),
                        ),
                      );
                    },
                    child: const Text(
                      'SKIP',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0070C0),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFF0070C0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    onPressed: _saveToFirestore,
                    child: const Text(
                      'NEXT STEP',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
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
