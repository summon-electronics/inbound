import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:inboundgenie/ConditionLineItemPage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'StepProgressBar.dart';

class Manufacturelabelpage extends StatefulWidget {
  const Manufacturelabelpage({Key? key}) : super(key: key);
  @override
  State<Manufacturelabelpage> createState() => _PackingSlipPageState();
}

class _PackingSlipPageState extends State<Manufacturelabelpage> {
  final picker = ImagePicker();
  File? _slipImage;
  String? _uploadedUrl;
  bool _isUploading = false;

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
                'PICK MANUFACTURE LABEL IMAGE',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              _buildOptionTile(
                icon: Icons.camera_alt,
                text: 'CAMERA',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              const SizedBox(height: 12),
              _buildOptionTile(
                icon: Icons.photo_library,
                text: 'GALLERY',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
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

  Future<void> _pickImage(ImageSource source) async {
    final XFile? file = await picker.pickImage(source: source);
    if (file == null) return;

    setState(() {
      _slipImage = File(file.path);
      _isUploading = true;
    });

    // Upload to storage and save to Firestore
    await _uploadAndSave();
  }

  Future<void> _ensureFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }

  Future<void> _uploadAndSave() async {
    await _ensureFirebase();
    try {
      final prefs = await SharedPreferences.getInstance();
      final poNumber = prefs.getString('selectedPoNumber') ?? '';
      final itemId = prefs.getString('selected_item_id') ?? '';

      if (poNumber.isEmpty || itemId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Purchase Order or Item selected')),
        );
        setState(() => _isUploading = false);
        return;
      }

      if (_slipImage == null) {
        setState(() => _isUploading = false);
        return;
      }

      // 1. Upload image to Firebase Storage with the requested path
      final ext = p.extension(_slipImage!.path).replaceFirst('.', '');
      final fileName = 'manufacturer_label/$poNumber/${itemId}_manufacturer_label.$ext';
      final ref = FirebaseStorage.instance.ref().child(fileName);
      await ref.putFile(_slipImage!);
      final imageUrl = await ref.getDownloadURL();

      // 2. Prepare the data
      final data = {
        'labelImageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // 3. Save to Firestore with the requested path
      await FirebaseFirestore.instance
          .collection('purchase_orders')
          .doc(poNumber)
          .collection('${itemId}_inspection')
          .doc('manufacturer_label')
          .set(data, SetOptions(merge: true));

      setState(() {
        _uploadedUrl = imageUrl;
        _isUploading = false;
      });

    } catch (e, st) {
      debugPrint('Firestore save error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
      setState(() => _isUploading = false);
    }
  }

  Future<void> _removeImage() async {
    if (_uploadedUrl != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final poNumber = prefs.getString('selectedPoNumber') ?? '';
        final itemId = prefs.getString('selected_item_id') ?? '';

        // Delete from Storage
        await FirebaseStorage.instance.refFromURL(_uploadedUrl!).delete();

        // Delete from Firestore
        await FirebaseFirestore.instance
            .collection('purchase_orders')
            .doc(poNumber)
            .collection('${itemId}_inspection')
            .doc('manufacturer_label_images')
            .update({
          'labelImageUrl': FieldValue.delete(),
        });
      } catch (e) {
        print("Deletion error: $e");
      }
    }
    setState(() {
      _slipImage = null;
      _uploadedUrl = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0070C0),
        title: const Text(
          'MANUFACTURE LABEL',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        leading: const BackButton(color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: StepProgressBar(
              currentStep: 6,
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
                    'UPLOAD THE MANUFACTURE LABEL IMAGE',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    textAlign: TextAlign.center,
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
                          onTap: _isUploading ? null : _showImagePickerDialog,
                          child: Container(
                            height: 200,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12),
                              ),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (_slipImage != null)
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(12),
                                    ),
                                    child: Image.file(
                                      _slipImage!,
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
                                if (_isUploading)
                                  Container(
                                    color: Colors.black54,
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                if (_slipImage != null && !_isUploading)
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                        ),
                                        onPressed: _removeImage,
                                      ),
                                    ),
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
                            'ADD MANUFACTURE LABEL IMAGE',
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const Conditionlineitempage(),
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
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const Conditionlineitempage(),
                        ),
                      );
                    },
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