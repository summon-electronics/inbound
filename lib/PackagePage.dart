import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:inboundgenie/WeightDimensionsPage.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'StepProgressBar.dart';

enum Slot { top, bottom, left, right, front, back }

class PackagePage extends StatefulWidget {
  const PackagePage({super.key});

  @override
  State<PackagePage> createState() => _PackagePageState();
}

class _PackagePageState extends State<PackagePage> {
  final ImagePicker _picker = ImagePicker();
  Slot? _activeSlot;
  XFile? _packageVideo;

  // Store only one image per slot
  final Map<Slot, XFile?> _slotImages = {for (var s in Slot.values) s: null};

  // Store upload status per slot
  final Map<Slot, bool> _slotUploading = {for (var s in Slot.values) s: false};

  // Store download URLs for uploaded images
  final Map<Slot, String?> _slotImageUrls = {
    for (var s in Slot.values) s: null,
  };

  // Store video upload status
  bool _videoUploading = false;
  String? _videoUrl;

  // Ensure Firebase initialized once if needed
  Future<void> _ensureFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }

  void _onSlotTap(Slot slot) {
    _activeSlot = slot;
    final viewLabel =
        '${slot.name[0].toUpperCase()}${slot.name.substring(1)} View';
    _showImagePickerDialog(viewLabel);
  }

  String _mimeTypeForExt(String ext) {
    ext = ext.toLowerCase();
    if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
    if (ext == 'png') return 'image/png';
    if (ext == 'gif') return 'image/gif';
    if (ext == 'mp4' || ext == 'mov' || ext == 'avi' || ext == 'mkv')
      return 'video/mp4';
    return 'application/octet-stream';
  }

  Future<void> _pickImage({required bool fromCamera}) async {
    if (_activeSlot == null) return;

    final XFile? file = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 85,
    );

    if (file != null) {
      setState(() {
        _slotImages[_activeSlot!] = file;
        _slotUploading[_activeSlot!] = true;
      });
      _uploadImageForSlot(_activeSlot!, file);
    }
  }

  Future<void> _uploadImageForSlot(Slot slot, XFile file) async {
    await _ensureFirebase();

    final prefs = await SharedPreferences.getInstance();
    final poNumber = prefs.getString('selectedPoNumber') ?? '';
    final itemId = prefs.getString('selected_item_id') ?? '';

    if (poNumber.isEmpty) {
      setState(() => _slotUploading[slot] = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No PO selected. Please select a PO first.')),
      );
      return;
    }

    if (itemId.isEmpty) {
      setState(() => _slotUploading[slot] = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No item selected. Please select an item first.')),
      );
      return;
    }

    try {
      final fileObj = File(file.path);
      final ext = p.extension(file.path).replaceFirst('.', '').toLowerCase();
      final mime = _mimeTypeForExt(ext);

      // Use itemId in filename so images are associated with the item
      final fileName = 'package_images/$poNumber/${itemId}_${slot.name}.$ext';
      final ref = FirebaseStorage.instance.ref().child(fileName);

      final metadata = SettableMetadata(contentType: mime);
      final uploadTask = ref.putFile(fileObj, metadata);

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      setState(() {
        _slotImageUrls[slot] = downloadUrl;
        _slotUploading[slot] = false;
      });
    } catch (e, st) {
      debugPrint('Image upload error for ${slot.name}: $e\n$st');
      setState(() => _slotUploading[slot] = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload ${slot.name} image')),
      );
    }
  }

  Future<void> _removeVideo() async {
    if (_videoUploading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video is uploading — wait to remove')),
      );
      return;
    }

    // If uploaded on storage, delete it
    if (_videoUrl != null) {
      try {
        await FirebaseStorage.instance.refFromURL(_videoUrl!).delete();
      } catch (e) {
        debugPrint('Failed to delete remote video: $e');
      }
    }

    // Clear local preview + url
    setState(() {
      _packageVideo = null;
      _videoUrl = null;
    });
  }

  Future<void> _onVideoCardTap() async {
    if (_videoUploading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video is uploading — wait until it finishes'),
        ),
      );
      return;
    }

    // If a video is already selected, ask whether to replace it
    if (_packageVideo != null) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Replace video?'),
          content: const Text(
            'A video is already attached. Do you want to replace it?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'CANCEL',
                style: TextStyle(color: Colors.blue),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('REPLACE', style: TextStyle(color: Colors.blue),),
            ),
          ],
        ),
      );

      if (replace != true) return;
    }

    _showVideoPickerDialog();
  }

  Future<void> _pickVideo({required bool fromCamera}) async {
    final XFile? file = await _picker.pickVideo(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );
    if (file == null) return;

    // If there is an already-uploaded video, try to delete its storage object first
    if (_videoUrl != null) {
      try {
        await FirebaseStorage.instance.refFromURL(_videoUrl!).delete();
      } catch (e) {
        debugPrint('Failed to delete previous video: $e');
      }
      setState(() => _videoUrl = null);
    }

    setState(() {
      _packageVideo = file;
      _videoUploading = true;
    });

    _uploadVideo(file);
  }

  Future<void> _uploadVideo(XFile file) async {
    await _ensureFirebase();

    final prefs = await SharedPreferences.getInstance();
    final poNumber = prefs.getString('selectedPoNumber') ?? '';
    final itemId = prefs.getString('selected_item_id') ?? '';

    if (poNumber.isEmpty) {
      setState(() => _videoUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No PO selected. Please select a PO first.')),
      );
      return;
    }

    if (itemId.isEmpty) {
      setState(() => _videoUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No item selected. Please select an item first.')),
      );
      return;
    }

    try {
      final fileObj = File(file.path);
      final ext = p.extension(file.path).replaceFirst('.', '').toLowerCase();
      final mime = _mimeTypeForExt(ext);

      // Use itemId in filename
      final fileName = 'packages/$poNumber/${itemId}_package_video.$ext';
      final ref = FirebaseStorage.instance.ref().child(fileName);

      final metadata = SettableMetadata(contentType: mime);
      final uploadTask = ref.putFile(fileObj, metadata);

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      setState(() {
        _videoUrl = downloadUrl;
        _videoUploading = false;
      });
    } catch (e, st) {
      debugPrint('Video upload error: $e\n$st');
      setState(() => _videoUploading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to upload video')));
    }
  }

  void _showImagePickerDialog(String viewLabel) {
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
              Text(
                'Pick Image for $viewLabel',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              _buildOptionTile(
                icon: Icons.camera_alt,
                text: 'Camera',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(fromCamera: true);
                },
              ),
              const SizedBox(height: 12),
              _buildOptionTile(
                icon: Icons.photo_library,
                text: 'Gallery',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(fromCamera: false);
                },
              ),
              const SizedBox(height: 20),
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

  void _showVideoPickerDialog() {
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
                'Pick Video',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              _buildOptionTile(
                icon: Icons.videocam,
                text: 'Record',
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo(fromCamera: true);
                },
              ),
              const SizedBox(height: 12),
              _buildOptionTile(
                icon: Icons.video_library,
                text: 'Gallery',
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo(fromCamera: false);
                },
              ),
              const SizedBox(height: 20),
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

  Widget _buildOptionTile({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF0070C0)),
      title: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18),
      ),
      onTap: onTap,
    );
  }

  /// Check if all required media is uploaded
  bool _areAllMediaUploaded() {
    // Check if all slot images are captured
    for (var slot in Slot.values) {
      if (_slotImages[slot] == null) return false;
    }

    // Check if video is captured
    if (_packageVideo == null) return false;

    return true;
  }

  bool _areAllUploadsComplete() {
    // Check if all slot images are uploaded
    for (var slot in Slot.values) {
      if (_slotImageUrls[slot] == null && _slotImages[slot] != null) {
        return false;
      }
    }

    // Check if video is uploaded
    if (_videoUrl == null && _packageVideo != null) {
      return false;
    }

    return true;
  }

  /// Save metadata to Firestore following the same pattern as WeightDimensionsPage
  Future<void> _saveToFirestore() async {
    await _ensureFirebase();

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

    try {
      // Prepare data similar to WeightDimensionsPage structure
      final data = {
        'topImageUrl': _slotImageUrls[Slot.top],
        'bottomImageUrl': _slotImageUrls[Slot.bottom],
        'leftImageUrl': _slotImageUrls[Slot.left],
        'rightImageUrl': _slotImageUrls[Slot.right],
        'frontImageUrl': _slotImageUrls[Slot.front],
        'backImageUrl': _slotImageUrls[Slot.back],
        'packageVideoUrl': _videoUrl,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Save to Firestore under purchase order inspections, named using itemIdCollection
      await FirebaseFirestore.instance
          .collection('purchase_orders')
          .doc(poNumber)
          .collection('${itemId}_inspection')
          .doc('package_images')
          .set(data, SetOptions(merge: true));

    } catch (e, st) {
      debugPrint('Firestore save error: $e\n$st');
      rethrow;
    }
  }

  /// Navigate to next page
  Future<void> _navigateToNext() async {
    if (!_areAllMediaUploaded()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please capture all 6 images and the video before proceeding',
          ),
        ),
      );
      return;
    }

    if (!_areAllUploadsComplete()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please wait for all images and video to finish uploading',
          ),
        ),
      );
      return;
    }

    try {
      // Save to Firestore before navigation
      await _saveToFirestore();

      // NAVIGATE AFTER SUCCESSFUL SAVE
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WeightDimensionsPage()),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0070C0),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'RECEIVED PACKAGE',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            StepProgressBar(
              currentStep: 1,
              totalSteps: 8,
              activeColor: const Color(0xFF0070C0),
              inactiveColor: Colors.grey.shade300,
              height: 4,
              spacing: 4,
            ),
            const SizedBox(height: 16),

            // Grid with images + video
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: size.width / (size.height / 2.5),
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              children: [
                ...Slot.values.map((slot) {
                  final label =
                      '${slot.name[0].toUpperCase()}${slot.name.substring(1)} View';
                  return _ImageCard(
                    label: label,
                    image: _slotImages[slot],
                    isUploading: _slotUploading[slot]!,
                    onTap: () => _onSlotTap(slot),
                    onRemove: () {
                      setState(() {
                        _slotImages[slot] = null;
                        _slotImageUrls[slot] = null;
                      });
                    },
                  );
                }).toList(),
                VideoCard(
                  label: 'Package Video',
                  video: _packageVideo,
                  isUploading: _videoUploading,
                  onTap: _onVideoCardTap,
                  onRemove: _removeVideo,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Actions (Skip / Next)
            Row(
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
                          builder: (_) => const WeightDimensionsPage(),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      backgroundColor: const Color(0xFF0070C0),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _navigateToNext,
                    child: const Text(
                      'NEXT STEP',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  final String label;
  final XFile? image;
  final bool isUploading;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _ImageCard({
    required this.label,
    required this.image,
    required this.isUploading,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (image == null) {
      content = const Center(
        child: Icon(Icons.add_a_photo, size: 24, color: Colors.grey),
      );
    } else {
      content = Stack(
        children: [
          Positioned.fill(
            child: Image.file(File(image!.path), fit: BoxFit.cover),
          ),
          if (isUploading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0070C0)),
                ),
              ),
            ),
          Positioned(
            right: 6,
            top: 6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(4),
                child: const Icon(Icons.close, size: 18, color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: content,
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF0070C0),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoCard extends StatefulWidget {
  final String label;
  final XFile? video;
  final bool isUploading;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const VideoCard({
    required this.label,
    required this.video,
    required this.isUploading,
    required this.onTap,
    required this.onRemove,
    super.key,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.video != null) {
      _initController();
    }
  }

  @override
  void didUpdateWidget(VideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video?.path != widget.video?.path && widget.video != null) {
      _initController();
    }
  }

  Future<void> _initController() async {
    _controller?.dispose();
    _controller = VideoPlayerController.file(File(widget.video!.path));
    await _controller!.initialize();
    setState(() {});
    _controller!.setLooping(true);
    _controller!.play();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: widget.video == null
                    ? const Center(
                  child: Icon(
                    Icons.videocam,
                    size: 48,
                    color: Colors.grey,
                  ),
                )
                    : Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child:
                      _controller != null &&
                          _controller!.value.isInitialized
                          ? AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      )
                          : const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    if (widget.isUploading)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF0070C0),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: GestureDetector(
                        onTap: widget.onRemove,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF0070C0),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Text(
                widget.label.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
