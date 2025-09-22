// Conditionlineitempage.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inboundgenie/FinalReportPage.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as p;
import 'StepProgressBar.dart';

enum Slot { top, bottom, left, right, front, back }

class Conditionlineitempage extends StatefulWidget {
  const Conditionlineitempage({Key? key}) : super(key: key);

  @override
  State<Conditionlineitempage> createState() => _ConditionLineItemPageState();
}

class _ConditionLineItemPageState extends State<Conditionlineitempage> {
  final ImagePicker _picker = ImagePicker();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // For the photo grid
  Slot? _activeSlot;
  XFile? _packageVideo;
  final Map<Slot, List<XFile>> _slotImages = {
    for (var s in Slot.values) s: <XFile>[],
  };
  final Map<Slot, List<String>> _slotImageUrls = {
    for (var s in Slot.values) s: <String>[],
  };

  // Screen-5 checklist state
  bool _hasAntistatic = false;
  bool _hasBubbleWrap = false;
  bool _labelsMatch = false;

  // Side-by-side images
  File? _exteriorImage;
  File? _interiorImage;
  String? _exteriorImageUrl;
  String? _interiorImageUrl;

  // Video
  String? _videoUrl;

  // Issue tags
  final Map<String, bool> _issues = {
    'Loose parts': false,
    'Double boxed': false,
    'No protection': false,
  };

  // Upload states
  final Map<Slot, bool> _slotUploading = {
    for (var s in Slot.values) s: false,
  };
  bool _exteriorUploading = false;
  bool _interiorUploading = false;
  bool _videoUploading = false;

  // Saving state
  bool _isSaving = false;

  // Firebase initialization guard
  Future<void> _ensureFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }

  // Get PO and item ID from shared preferences
  Future<Map<String, String>> _getPoAndItemId() async {
    final prefs = await SharedPreferences.getInstance();
    final poNumber = prefs.getString('selectedPoNumber') ?? '';
    final itemId = prefs.getString('selected_item_id') ?? '';
    return {'poNumber': poNumber, 'itemId': itemId};
  }

  // ——— Helpers for image/video picking and uploading ———

  void _onSlotTap(Slot slot) {
    _activeSlot = slot;
    final viewLabel =
        '${slot.name[0].toUpperCase()}${slot.name.substring(1)} View';
    _showImagePickerDialog(viewLabel, forSlot: true);
  }

  Future<void> _showImagePickerDialog(String title,
      {bool forSlot = false, bool forSide = false, String? sideType}) async {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Pick Image for $title',
                style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF0070C0)),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera,
                    forSlot: forSlot, forSide: forSide, sideType: sideType);
              },
            ),
            ListTile(
              leading:
              const Icon(Icons.photo_library, color: Color(0xFF0070C0)),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery,
                    forSlot: forSlot, forSide: forSide, sideType: sideType);
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL', style: TextStyle(color: Colors.red)),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source,
      {bool forSlot = false, bool forSide = false, String? sideType}) async {
    final XFile? file = await _picker.pickImage(source: source);
    if (file == null) return;

    if (forSlot && _activeSlot != null) {
      setState(() {
        _slotImages[_activeSlot!]!.add(file);
        _slotUploading[_activeSlot!] = true;
      });
      await _uploadSlotImage(file, _activeSlot!);
    } else if (forSide && sideType != null) {
      if (sideType == 'exterior') {
        setState(() {
          _exteriorImage = File(file.path);
          _exteriorUploading = true;
        });
        await _uploadSideImage(File(file.path), 'exterior');
      } else if (sideType == 'interior') {
        setState(() {
          _interiorImage = File(file.path);
          _interiorUploading = true;
        });
        await _uploadSideImage(File(file.path), 'interior');
      }
    }
  }

  Future<void> _uploadSlotImage(XFile file, Slot slot) async {
    try {
      final ids = await _getPoAndItemId();
      final poNumber = ids['poNumber'] ?? '';
      final itemId = ids['itemId'] ?? '';

      if (poNumber.isEmpty || itemId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No PO or item selected')),
        );
        setState(() => _slotUploading[slot] = false);
        return;
      }

      final imageFile = File(file.path);
      final ext = p.extension(file.path).replaceFirst('.', '');
      // Use the requested file path pattern
      final fileName = 'open_box/$poNumber/${itemId}_${slot.name}.$ext';
      final ref = _storage.ref().child(fileName);

      final uploadTask = ref.putFile(imageFile);
      await uploadTask;
      final downloadUrl = await ref.getDownloadURL();

      setState(() {
        _slotImageUrls[slot]!.add(downloadUrl);
        _slotUploading[slot] = false;
      });
    } catch (e) {
      print("Upload error: $e");
      setState(() => _slotUploading[slot] = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to upload image")),
        );
      }
    }
  }

  Future<void> _uploadSideImage(File image, String type) async {
    try {
      final ids = await _getPoAndItemId();
      final poNumber = ids['poNumber'] ?? '';
      final itemId = ids['itemId'] ?? '';

      if (poNumber.isEmpty || itemId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No PO or item selected')),
        );
        setState(() {
          if (type == 'exterior') _exteriorUploading = false;
          else _interiorUploading = false;
        });
        return;
      }

      final ext = p.extension(image.path).replaceFirst('.', '');
      // Use the requested file path pattern
      final fileName = 'open_box/$poNumber/${itemId}_$type.$ext';
      final ref = _storage.ref().child(fileName);

      final uploadTask = ref.putFile(image);
      await uploadTask;
      final downloadUrl = await ref.getDownloadURL();

      setState(() {
        if (type == 'exterior') {
          _exteriorImageUrl = downloadUrl;
          _exteriorUploading = false;
        } else {
          _interiorImageUrl = downloadUrl;
          _interiorUploading = false;
        }
      });
    } catch (e) {
      print("Upload error: $e");
      setState(() {
        if (type == 'exterior') {
          _exteriorUploading = false;
        } else {
          _interiorUploading = false;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to upload image")),
        );
      }
    }
  }

  void _showVideoPickerDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Pick Video',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.videocam, color: Color(0xFF0070C0)),
              title: const Text('Record'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo(true);
              },
            ),
            ListTile(
              leading:
              const Icon(Icons.video_library, color: Color(0xFF0070C0)),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo(false);
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL', style: TextStyle(color: Colors.red)),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickVideo(bool fromCamera) async {
    final XFile? file = await _picker.pickVideo(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery);
    if (file == null) return;

    setState(() {
      _packageVideo = file;
      _videoUploading = true;
    });

    await _uploadVideo(File(file.path));
  }

  Future<void> _uploadVideo(File video) async {
    try {
      final ids = await _getPoAndItemId();
      final poNumber = ids['poNumber'] ?? '';
      final itemId = ids['itemId'] ?? '';

      if (poNumber.isEmpty || itemId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No PO or item selected')),
        );
        setState(() => _videoUploading = false);
        return;
      }

      final ext = p.extension(video.path).replaceFirst('.', '');
      // Use the requested file path pattern
      final fileName = 'open_box/$poNumber/${itemId}_video.$ext';
      final ref = _storage.ref().child(fileName);

      final uploadTask = ref.putFile(video);
      await uploadTask;
      final downloadUrl = await ref.getDownloadURL();

      setState(() {
        _videoUrl = downloadUrl;
        _videoUploading = false;
      });
    } catch (e) {
      print("Upload error: $e");
      setState(() => _videoUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to upload video")),
        );
      }
    }
  }

  bool _anyUploadInProgress() {
    if (_exteriorUploading || _interiorUploading || _videoUploading) return true;
    for (var s in Slot.values) {
      if (_slotUploading[s] == true) return true;
    }
    return false;
  }

  /// Save all collected data (image URLs, checklist, tags) to Firestore
  Future<void> _saveToFirestore() async {
    if (_isSaving) return;

    if (_anyUploadInProgress()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for uploads to finish before saving.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _ensureFirebase();
      final ids = await _getPoAndItemId();
      final poNumber = ids['poNumber'] ?? '';
      final itemId = ids['itemId'] ?? '';

      if (poNumber.isEmpty || itemId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Purchase Order or item selected')),
        );
        setState(() => _isSaving = false);
        return;
      }

      // Convert slot urls map to serializable map with string keys
      final Map<String, List<String>> slotUrls = {
        for (var s in Slot.values) s.name: List.unmodifiable(_slotImageUrls[s] ?? [])
      };

      // Convert selected issues into list
      final List<String> selectedIssues = _issues.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      final data = <String, dynamic>{
        'slotImageUrls': slotUrls,
        'exteriorImageUrl': _exteriorImageUrl,
        'interiorImageUrl': _interiorImageUrl,
        'videoUrl': _videoUrl,
        'hasAntistatic': _hasAntistatic,
        'hasBubbleWrap': _hasBubbleWrap,
        'labelsMatch': _labelsMatch,
        'issues': selectedIssues,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Use the requested Firestore path
      await FirebaseFirestore.instance
          .collection('purchase_orders')
          .doc(poNumber)
          .collection('${itemId}_inspection')
          .doc('open_box')
          .set(data, SetOptions(merge: true));

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FinalReportPage()),
        );
      }
        } catch (e) {
      print('Error saving to Firestore: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
      } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ——— Build ———

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0070C0),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(' OPEN BOX INSPECTION',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(children: [
          // Progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: StepProgressBar(
              currentStep: 7,
              totalSteps: 8,
              activeColor: const Color(0xFF0070C0),
              inactiveColor: Colors.grey.shade300,
              height: 4,
              spacing: 4,
            ),
          ),

          // Photo & video grid
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: size.width / (size.height / 2.5),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var slot in Slot.values)
                  _ImageCard(
                    label:
                    '${slot.name[0].toUpperCase()}${slot.name.substring(1)} View',
                    images: _slotImages[slot]!,
                    onTap: () => _onSlotTap(slot),
                    showProgress: _slotUploading[slot]!,
                  ),
                VideoCard(
                  label: 'OPEN BOX VIDEO',
                  video: _packageVideo,
                  onTap: _showVideoPickerDialog,
                  uploading: _videoUploading,
                ),
              ],
            ),
          ),

          // Checklist heading
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Packaging Checklist',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ),
          ),
          // Checklist
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              CheckboxListTile(
                title: const Text('Antistatic bag present'),
                value: _hasAntistatic,
                onChanged: (v) => setState(() => _hasAntistatic = v!),
              ),
              CheckboxListTile(
                title: const Text('Bubble wrap present'),
                value: _hasBubbleWrap,
                onChanged: (v) => setState(() => _hasBubbleWrap = v!),
              ),
              CheckboxListTile(
                title: const Text('Labels match box exterior'),
                value: _labelsMatch,
                onChanged: (v) => setState(() => _labelsMatch = v!),
              ),
            ]),
          ),
          const Divider(),

          // Side-by-side exterior/interior
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Expanded(
                child: _SideImageCard(
                  label: 'Box Exterior',
                  image: _exteriorImage,
                  onTap: () => _showImagePickerDialog(
                      'Box Exterior', forSide: true, sideType: 'exterior'),
                  showProgress: _exteriorUploading,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SideImageCard(
                  label: 'Box Interior',
                  image: _interiorImage,
                  onTap: () => _showImagePickerDialog(
                      'Box Interior', forSide: true, sideType: 'interior'),
                  showProgress: _interiorUploading,
                ),
              ),
            ]),
          ),
          const Divider(),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tag any packaging issues:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ),
          ),
          // Issue tags
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _issues.keys.map((key) {
                return FilterChip(
                  label: Text(key),
                  selected: _issues[key]!,
                  onSelected: (sel) => setState(() => _issues[key] = sel),
                );
              }).toList(),
            ),
          ),
          const Divider(),

          // Skip & Next row
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side:
                    const BorderSide(color: Color(0xFF0070C0), width: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FinalReportPage()),
                  ),
                  child: const Text('SKIP',
                      style: TextStyle(
                          color: Color(0xFF0070C0),
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0070C0),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _isSaving || _anyUploadInProgress()
                      ? null
                      : () => _saveToFirestore(),
                  child: _isSaving
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : const Text('NEXT STEP',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Side-by-side image card
class _SideImageCard extends StatelessWidget {
  final String label;
  final File? image;
  final VoidCallback onTap;
  final bool showProgress;

  const _SideImageCard({
    required this.label,
    required this.image,
    required this.onTap,
    required this.showProgress,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Column(children: [
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: image != null
                    ? ClipRRect(
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
                  child: Image.file(image!, fit: BoxFit.cover),
                )
                    : const Center(
                  child: Icon(Icons.add_photo_alternate,
                      size: 32, color: Colors.grey),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF0070C0),
                  borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(12)),
                ),
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ]),
            if (showProgress)
              Container(
                color: Colors.black54,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

/// Reusable image-grid card
class _ImageCard extends StatelessWidget {
  final String label;
  final List<XFile> images;
  final VoidCallback onTap;
  final bool showProgress;

  const _ImageCard({
    required this.label,
    required this.images,
    required this.onTap,
    required this.showProgress,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (images.isEmpty) {
      content = const Center(
        child: Icon(Icons.add_a_photo, size: 24, color: Colors.grey),
      );
    } else if (images.length == 1) {
      content = Image.file(File(images.first.path), fit: BoxFit.cover);
    } else {
      content = GridView.builder(
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
        itemCount: images.length,
        itemBuilder: (context, i) =>
            Image.file(File(images[i].path), fit: BoxFit.cover),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        child: Stack(
          children: [
            Column(children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: content,
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF0070C0),
                  borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: Text(label.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ]),
            if (showProgress)
              Container(
                color: Colors.black54,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

/// Video card widget
class VideoCard extends StatefulWidget {
  final String label;
  final XFile? video;
  final VoidCallback onTap;
  final bool uploading;

  const VideoCard({
    required this.label,
    required this.video,
    required this.onTap,
    required this.uploading,
    Key? key,
  }) : super(key: key);

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.video != null) _initController();
  }

  @override
  void didUpdateWidget(VideoCard old) {
    super.didUpdateWidget(old);
    if (old.video?.path != widget.video?.path && widget.video != null) {
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
        child: Stack(
          children: [
            Column(children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: widget.video == null
                      ? const Center(
                    child: Icon(Icons.videocam,
                        size: 48, color: Colors.grey),
                  )
                      : ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16)),
                    child: _controller != null &&
                        _controller!.value.isInitialized
                        ? AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    )
                        : const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF0070C0),
                  borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: Text(widget.label.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ]),
            if (widget.uploading)
              Container(
                color: Colors.black54,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}