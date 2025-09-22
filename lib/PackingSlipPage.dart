import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:inboundgenie/ManufactureLabelPage.dart';
import 'StepProgressBar.dart';

class PackingSlipPage extends StatefulWidget {
  const PackingSlipPage({Key? key}) : super(key: key);

  @override
  State<PackingSlipPage> createState() => _PackingSlipPageState();
}

class _PackingSlipPageState extends State<PackingSlipPage> {
  final picker = ImagePicker();
  final List<File> _slipImages = [];
  final List<String> _uploadedUrls = [];
  final List<bool> _uploadingStatus = []; // Track upload status for each image

  bool _isMatch = false;
  bool _isConfirmed = false;
  String _notes = '';
  final TextEditingController _notesController = TextEditingController();

  // Ensure Firebase initialized once if needed
  Future<void> _ensureFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }

  /// ---------------- IMAGE PICKER & UPLOAD ----------------
  Future<void> _uploadImage(File image, int index) async {
    await _ensureFirebase();

    final prefs = await SharedPreferences.getInstance();
    final poNumber = prefs.getString('selectedPoNumber') ?? '';
    final itemId = prefs.getString('selected_item_id') ?? '';

    if (poNumber.isEmpty || itemId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No PO or item selected. Please select first.')),
      );
      return;
    }

    try {
      setState(() {
        _uploadingStatus[index] = true;
      });

      final ext = p.extension(image.path).replaceFirst('.', '').toLowerCase();
      // Use the requested file path pattern
      final fileName = 'package_slip/$poNumber/${itemId}_packing_slip_$index.$ext';
      final ref = FirebaseStorage.instance.ref().child(fileName);

      await ref.putFile(image);
      final downloadUrl = await ref.getDownloadURL();

      setState(() {
        _uploadedUrls.add(downloadUrl);
        _uploadingStatus[index] = false;
      });
    } catch (e) {
      debugPrint("Upload failed: $e");
      setState(() {
        _uploadingStatus[index] = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload image: $e')),
      );
    }
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
                'PICK PACKING SLIP IMAGE',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              _buildOptionTile(
                icon: Icons.camera_alt,
                text: 'TAKE PHOTO',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              const SizedBox(height: 12),
              _buildOptionTile(
                icon: Icons.photo_library,
                text: 'CHOOSE FROM GALLERY',
                onTap: () {
                  Navigator.pop(context);
                  _pickMultipleImages();
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
      tileColor: Colors.grey[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(icon, color: const Color(0xFF0070C0)),
      title: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      onTap: onTap,
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? file = await picker.pickImage(source: source);
    if (file != null) {
      final imageFile = File(file.path);
      final newIndex = _slipImages.length;

      setState(() {
        _slipImages.add(imageFile);
        _uploadingStatus.add(true);
      });

      // Start upload immediately
      await _uploadImage(imageFile, newIndex);
    }
  }

  Future<void> _pickMultipleImages() async {
    final List<XFile> files = await picker.pickMultiImage();
    if (files.isNotEmpty) {
      for (var file in files) {
        final imageFile = File(file.path);
        final newIndex = _slipImages.length;

        setState(() {
          _slipImages.add(imageFile);
          _uploadingStatus.add(true);
        });

        // Start upload immediately for each image
        _uploadImage(imageFile, newIndex);
      }
    }
  }

  void _removeImage(int index) async {
    // Remove from local lists
    setState(() {
      _slipImages.removeAt(index);
      if (index < _uploadedUrls.length) {
        final url = _uploadedUrls[index];
        _uploadedUrls.removeAt(index);

        // Delete from Firebase Storage
        try {
          FirebaseStorage.instance.refFromURL(url).delete();
        } catch (e) {
          debugPrint("Error deleting image: $e");
        }
      }
      _uploadingStatus.removeAt(index);
    });
  }

  /// ---------------- SAVE TO FIRESTORE ----------------
  Future<void> _saveToFirestore() async {
    await _ensureFirebase();

    final prefs = await SharedPreferences.getInstance();
    final poNumber = prefs.getString('selectedPoNumber') ?? '';
    final itemId = prefs.getString('selected_item_id') ?? '';

    if (poNumber.isEmpty || itemId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No Purchase Order or item selected')),
      );
      return;
    }

    try {
      // Prepare data following the requested pattern
      final data = {
        'isMatch': _isMatch,
        'isConfirmed': _isConfirmed,
        'notes': _notes,
        'imageUrls': _uploadedUrls,
        'imageCount': _uploadedUrls.length,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Save to Firestore using the requested path
      await FirebaseFirestore.instance
          .collection('purchase_orders')
          .doc(poNumber)
          .collection('${itemId}_inspection')
          .doc('package_slip')
          .set(data, SetOptions(merge: true));

    } catch (e, st) {
      debugPrint('Firestore save error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
      rethrow;
    }
  }

  /// ---------------- CONFIRMATION DIALOG ----------------
  void _showConfirmationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text(
              'Confirm Packing Slip',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Does this match the packing list?',
                  style: TextStyle(color: Colors.black),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isMatch
                            ? const Color(0xFF0070C0)
                            : Colors.grey,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                      onPressed: () {
                        setStateDialog(() => _isMatch = true);
                      },
                      child: const Text(
                        'YES',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: !_isMatch
                            ? Colors.red
                            : Colors.grey,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                      onPressed: () {
                        setStateDialog(() => _isMatch = false);
                      },
                      child: const Text(
                        'NO',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                if (!_isMatch) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Please provide notes:',
                    style: TextStyle(color: Colors.black),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Enter details about the mismatch...',
                      hintStyle: TextStyle(color: Colors.grey),
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                ]
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL',
                    style: TextStyle(color: Colors.black)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0070C0)),
                onPressed: () {
                  if (!_isMatch && _notesController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                          Text("Please provide notes for mismatch")),
                    );
                    return;
                  }

                  _notes = _notesController.text;
                  setState(() {
                    _isConfirmed = true;
                  });
                  Navigator.pop(context);
                },
                child: const Text('CONFIRM',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _proceedToNextPage() async {
    if (!_isConfirmed && _slipImages.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please confirm packing slip first")));
      return;
    }

    try {
      // Save data to Firestore before navigation
      if (_slipImages.isNotEmpty) {
        await _saveToFirestore();
      }

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => Manufacturelabelpage()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save data: $e')),
      );
    }
  }

  /// ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0070C0),
        title: const Text(
          'PACKING SLIP',
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
        ),
        centerTitle: true,
        leading: const BackButton(color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: StepProgressBar(
              currentStep: 5,
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
                  const Text('UPLOAD THE PACKING SLIP IMAGE',
                      style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  const Text('Capture clear images of the packing slip',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 20),

                  Center(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0070C0),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                      ),
                      onPressed: _showImagePickerDialog,
                      icon: const Icon(Icons.add_a_photo, color: Colors.white),
                      label: const Text('Add Images',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ),
                  ),

                  const SizedBox(height: 20),

                  if (_slipImages.isNotEmpty)
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.8,
                      ),
                      itemCount: _slipImages.length,
                      itemBuilder: (context, index) {
                        return Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.white,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  _slipImages[index],
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              ),
                            ),
                            if (_uploadingStatus[index])
                              Positioned.fill(
                                child: Container(
                                  color: Colors.black54,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: CircleAvatar(
                                backgroundColor: Colors.black54,
                                radius: 16,
                                child: IconButton(
                                  icon: const Icon(Icons.close,
                                      size: 16, color: Colors.white),
                                  onPressed: () => _removeImage(index),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),

          /// FOOTER BUTTONS
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
                          color: Color(0xFF0070C0), width: 2),
                    ),
                    onPressed: () => _proceedToNextPage(),
                    child: const Text('SKIP',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0070C0))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFF0070C0),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: () {
                      if (_slipImages.isEmpty) {
                        // Skip directly if no images
                        _proceedToNextPage();
                      } else if (!_isConfirmed) {
                        // Show confirmation dialog if not confirmed
                        _showConfirmationDialog();
                      } else {
                        // Proceed to next page
                        _proceedToNextPage();
                      }
                    },
                    child: Text(
                      _isConfirmed ? 'NEXT STEP' : 'CONFIRM SLIP',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
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