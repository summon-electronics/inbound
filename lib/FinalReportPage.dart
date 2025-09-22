// FinalReportPage.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'pdf_service.dart';
import 'HomePage.dart';
import 'StepProgressBar.dart';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FinalReportPage extends StatefulWidget {
  final File? packageImage;
  final File? interiorImage;
  final File? manufacturerLabelImage;
  final File? conditionLineImage;
  final File? slipImage;
  final File? weightImage;
  final File? lenghtImage;
  final File? heightImage;
  final File? widthImage;
  final File? packageVideo;
  final File? conditionVideo;
  final String length;
  final String width;
  final String height;
  final String weight;
  final bool hasTestReports;

  const FinalReportPage({
    Key? key,
    this.packageImage,
    this.interiorImage,
    this.manufacturerLabelImage,
    this.conditionLineImage,
    this.slipImage,
    this.weightImage,
    this.lenghtImage,
    this.heightImage,
    this.widthImage,
    this.packageVideo,
    this.conditionVideo,
    this.length = '',
    this.width = '',
    this.height = '',
    this.weight = '',
    this.hasTestReports = false,
  }) : super(key: key);

  @override
  State<FinalReportPage> createState() => _FinalReportPageState();
}

class _FinalReportPageState extends State<FinalReportPage> {
  final ImagePicker _picker = ImagePicker();
  bool _isGeneratingPdf = false;

  // fetched URLs (nullable)
  String? _packageTopUrl;
  String? _packageBottomUrl;
  String? _packageLeftUrl;
  String? _packageRightUrl;
  String? _packageFrontUrl;
  String? _packageBackUrl;
  String? _packageVideoUrl;

  String? _condTopUrl;
  String? _condBottomUrl;
  String? _condLeftUrl;
  String? _condRightUrl;
  String? _condFrontUrl;
  String? _condBackUrl;
  String? _conditionVideoUrl;

  String? _interiorImageUrl;
  String? _interiorTestReportAnswer;

  String? _weightImageUrl;
  String? _lengthImageUrl;
  String? _heightImageUrl;
  String? _widthImageUrl;

  List<String> _slipImageUrls = [];
  String? _slipIsMatch;
  String? _slipNotes;

  Map<String, dynamic>? _openBoxData;

  // Open Box Inspection data
  List<String> _openBoxIssues = [];
  bool _hasAntistatic = false;
  bool _hasBubbleWrap = false;
  bool _labelsMatch = false;
  String? _openBoxExteriorImageUrl;
  String? _openBoxInteriorImageUrl;

  // weight/dimensions values fetched from Firestore (used when widget fields are empty)
  String? _weightValue;
  String? _lengthValue;
  String? _heightValue;
  String? _widthValue;

  // simple loading flag for fetching
  bool _isFetching = true;
  String? _fetchError;
  String? _manufacturerLabelUrl;

  // po/item context
  String? _poNumber;
  String? _itemId;

  // Initialize with a `checked` field to avoid nulls (kept for checklist UI)
  final List<Map<String, dynamic>> poItems = [
    {
      'checked': false,
      'name': 'PO-02530', // dummy PO #
      'photo': null,
      'status': 'Received',
      'qty': '',
      'comment': ''
    },
    {
      'checked': false,
      'name': 'PO-03721',
      'photo': null,
      'status': 'Missing',
      'qty': '',
      'comment': ''
    },
    {
      'checked': false,
      'name': 'PO-04892',
      'photo': null,
      'status': 'Wrong Part',
      'qty': '',
      'comment': ''
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchInspectionData();
    _loadManufacturerLabel();
  }

  Future<void> _ensureFirebase() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  }

  /// Fetch all relevant inspection documents for the currently-selected PO & item
  Future<void> _fetchInspectionData() async {
    setState(() {
      _isFetching = true;
      _fetchError = null;
    });

    try {
      await _ensureFirebase();
      final prefs = await SharedPreferences.getInstance();
      final poNumber = prefs.getString('selectedPoNumber') ?? '';
      final itemId = prefs.getString('selected_item_id') ?? '';

      if (poNumber.isEmpty || itemId.isEmpty) {
        setState(() {
          _fetchError = 'PO number or item id not found in SharedPreferences';
          _isFetching = false;
        });
        return;
      }

      _poNumber = poNumber;
      _itemId = itemId;

      final base = FirebaseFirestore.instance
          .collection('purchase_orders')
          .doc(poNumber)
          .collection('${itemId}_inspection');

      // package_images doc
      final packageSnap = await base.doc('package_images').get();
      if (packageSnap.exists) {
        final d = packageSnap.data()!;
        _packageTopUrl = (d['topImageUrl'] as String?)?.isNotEmpty == true ? d['topImageUrl'] as String : null;
        _packageBottomUrl = (d['bottomImageUrl'] as String?)?.isNotEmpty == true ? d['bottomImageUrl'] as String : null;
        _packageLeftUrl = (d['leftImageUrl'] as String?)?.isNotEmpty == true ? d['leftImageUrl'] as String : null;
        _packageRightUrl = (d['rightImageUrl'] as String?)?.isNotEmpty == true ? d['rightImageUrl'] as String : null;
        _packageFrontUrl = (d['frontImageUrl'] as String?)?.isNotEmpty == true ? d['frontImageUrl'] as String : null;
        _packageBackUrl = (d['backImageUrl'] as String?)?.isNotEmpty == true ? d['backImageUrl'] as String : null;
        _packageVideoUrl = (d['packageVideoUrl'] as String?)?.isNotEmpty == true ? d['packageVideoUrl'] as String : null;
      }

      // weight_dimensions doc
      final weightSnap = await base.doc('weight_dimensions').get();
      if (weightSnap.exists) {
        final d = weightSnap.data()!;
        _weightImageUrl = (d['weightImageUrl'] as String?)?.isNotEmpty == true ? d['weightImageUrl'] as String : null;
        _lengthImageUrl = (d['lengthImageUrl'] as String?)?.isNotEmpty == true ? d['lengthImageUrl'] as String : null;
        _heightImageUrl = (d['heightImageUrl'] as String?)?.isNotEmpty == true ? d['heightImageUrl'] as String : null;
        _widthImageUrl = (d['widthImageUrl'] as String?)?.isNotEmpty == true ? d['widthImageUrl'] as String : null;

        // read numeric/text fields if present and store into the state fallback vars
        if (d['weight'] != null) _weightValue = d['weight'].toString();
        if (d['length'] != null) _lengthValue = d['length'].toString();
        if (d['height'] != null) _heightValue = d['height'].toString();
        if (d['width'] != null) _widthValue = d['width'].toString();
      }

      // package_interior_images doc
      final interiorSnap = await base.doc('package_interior').get();
      if (interiorSnap.exists) {
        final d = interiorSnap.data()!;
        _interiorImageUrl = (d['interiorImageUrl'] as String?)?.isNotEmpty == true ? d['interiorImageUrl'] as String : null;
        _interiorTestReportAnswer = (d['testReportAnswer'] as String?) ?? (d['testReport'] as String?);
      }

      // package_slip_images doc
      final slipSnap = await base.doc('package_slip').get();
      if (slipSnap.exists) {
        final d = slipSnap.data()!;
        final list = (d['imageUrls'] as List<dynamic>?)?.cast<String>() ?? [];
        _slipImageUrls = list.where((s) => s.isNotEmpty).toList();

        // fix: isMatch is boolean in Firestore
        final matchVal = d['isMatch'];
        if (matchVal is bool) {
          _slipIsMatch = matchVal ? 'YES' : 'NO';
        } else {
          _slipIsMatch = matchVal?.toString();
        }

        _slipNotes = d['notes'] as String?;
      }

      // OPEN BOX INSPECTION DATA (from Conditionlineitempage)
      final openBoxSnap = await base.doc('open_box').get();
      if (openBoxSnap.exists) {
        _openBoxData = openBoxSnap.data();

        // Extract open box data
        if (_openBoxData != null) {
          setState(() {
            _hasAntistatic = _openBoxData!['hasAntistatic'] ?? false;
            _hasBubbleWrap = _openBoxData!['hasBubbleWrap'] ?? false;
            _labelsMatch = _openBoxData!['labelsMatch'] ?? false;
            _openBoxIssues = List<String>.from(_openBoxData!['issues'] ?? []);

            // Set condition images from open_box data
            final slotImageUrls = _openBoxData!['slotImageUrls'] as Map<String, dynamic>?;
            if (slotImageUrls != null) {
              _condTopUrl = slotImageUrls['top'] is List && (slotImageUrls['top'] as List).isNotEmpty
                  ? (slotImageUrls['top'] as List).first : null;
              _condBottomUrl = slotImageUrls['bottom'] is List && (slotImageUrls['bottom'] as List).isNotEmpty
                  ? (slotImageUrls['bottom'] as List).first : null;
              _condLeftUrl = slotImageUrls['left'] is List && (slotImageUrls['left'] as List).isNotEmpty
                  ? (slotImageUrls['left'] as List).first : null;
              _condRightUrl = slotImageUrls['right'] is List && (slotImageUrls['right'] as List).isNotEmpty
                  ? (slotImageUrls['right'] as List).first : null;
              _condFrontUrl = slotImageUrls['front'] is List && (slotImageUrls['front'] as List).isNotEmpty
                  ? (slotImageUrls['front'] as List).first : null;
              _condBackUrl = slotImageUrls['back'] is List && (slotImageUrls['back'] as List).isNotEmpty
                  ? (slotImageUrls['back'] as List).first : null;
            }

            // Set condition video from open_box data
            _conditionVideoUrl = _openBoxData!['videoUrl'] as String?;

            // Set exterior and interior images from open_box data
            _openBoxExteriorImageUrl = _openBoxData!['exteriorImageUrl'] as String?;
            _openBoxInteriorImageUrl = _openBoxData!['interiorImageUrl'] as String?;
          });
        }
      }

      setState(() {
        _isFetching = false;
      });
    } catch (e, st) {
      debugPrint('Failed to fetch inspection data: $e\n$st');
      setState(() {
        _fetchError = 'Failed to fetch inspection data';
        _isFetching = false;
      });
    }
  }

  Future<void> _loadManufacturerLabel() async {
    final prefs = await SharedPreferences.getInstance();
    final poNumber = prefs.getString('selectedPoNumber') ?? '';
    final itemId = prefs.getString('selected_item_id') ?? '';

    if (poNumber.isEmpty || itemId.isEmpty) return;

    final snap = await FirebaseFirestore.instance
        .collection('purchase_orders')
        .doc(poNumber)
        .collection('${itemId}_inspection')
        .doc('manufacturer_label')
        .get();

    if (snap.exists) {
      setState(() {
        _manufacturerLabelUrl = snap.data()?['labelImageUrl'] as String?;
      });
    }
  }

  /// Download URL to temporary File for PDF generation (returns null on failure)
  Future<File?> _downloadToTempFile(String url, {String? prefix}) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return null;
      final bytes = res.bodyBytes;
      final dir = await getTemporaryDirectory();
      final name = '${prefix ?? 'img'}_${DateTime.now().millisecondsSinceEpoch}';
      // try to infer extension
      String ext = '';
      final uri = Uri.parse(url);
      final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
      if (last != null && last.contains('.')) {
        ext = '.${last.split('.').last}';
      } else {
        ext = '.jpg';
      }
      final file = File('${dir.path}/$name$ext');
      await file.writeAsBytes(bytes);
      return file;
    } catch (e, st) {
      debugPrint('Error downloading $url : $e\n$st');
      return null;
    }
  }

  /// prepare File lists for PdfService.generateFinalReportPdf:
  /// use local files passed in widget when available; otherwise download remote URLs to temp files.
  /// prepare File lists for PdfService.generateFinalReportPdf:
  /// use local files passed in widget when available; otherwise download remote URLs to temp files.
  Future<void> _generatePdf() async {
    setState(() => _isGeneratingPdf = true);
    try {
      // ---------------- exterior images ----------------
      final List<File> exteriorFiles = [];
      final candidates = <dynamic>[
        widget.packageImage ?? _packageTopUrl,
        widget.packageImage ?? _packageBottomUrl,
        widget.packageImage ?? _packageLeftUrl,
        widget.packageImage ?? _packageRightUrl,
        widget.packageImage ?? _packageFrontUrl,
        widget.packageImage ?? _packageBackUrl,
      ];
      for (var c in candidates) {
        if (c == null) continue;
        if (c is File) {
          exteriorFiles.add(c);
        } else if (c is String) {
          final f = await _downloadToTempFile(c, prefix: 'exterior');
          if (f != null) exteriorFiles.add(f);
        }
      }

      // ---------------- condition images ----------------
      final List<File> conditionFiles = [];
      final condCandidates = <dynamic>[
        widget.conditionLineImage ?? _condTopUrl,
        widget.conditionLineImage ?? _condBottomUrl,
        widget.conditionLineImage ?? _condLeftUrl,
        widget.conditionLineImage ?? _condRightUrl,
        widget.conditionLineImage ?? _condFrontUrl,
        widget.conditionLineImage ?? _condBackUrl,
      ];
      for (var c in condCandidates) {
        if (c == null) continue;
        if (c is File) {
          conditionFiles.add(c);
        } else if (c is String) {
          final f = await _downloadToTempFile(c, prefix: 'condition');
          if (f != null) conditionFiles.add(f);
        }
      }

      // ---------------- interior image ----------------
      File? interiorFile = widget.interiorImage;
      if (interiorFile == null && _interiorImageUrl != null) {
        interiorFile = await _downloadToTempFile(_interiorImageUrl!, prefix: 'interior');
      }

      // ---------------- slip image ----------------
      File? slipFile = widget.slipImage;
      if (slipFile == null && _slipImageUrls.isNotEmpty) {
        slipFile = await _downloadToTempFile(_slipImageUrls.first, prefix: 'slip');
      }

      // ---------------- weight/measurement images ----------------
      File? weightFile = widget.weightImage;
      if (weightFile == null && _weightImageUrl != null) {
        weightFile = await _downloadToTempFile(_weightImageUrl!, prefix: 'weight');
      }

      File? lengthFile = widget.lenghtImage;
      if (lengthFile == null && _lengthImageUrl != null) {
        lengthFile = await _downloadToTempFile(_lengthImageUrl!, prefix: 'length');
      }

      File? widthFile = widget.widthImage;
      if (widthFile == null && _widthImageUrl != null) {
        widthFile = await _downloadToTempFile(_widthImageUrl!, prefix: 'width');
      }

      File? heightFile = widget.heightImage;
      if (heightFile == null && _heightImageUrl != null) {
        heightFile = await _downloadToTempFile(_heightImageUrl!, prefix: 'height');
      }

      // ---------------- manufacturer label ----------------
      // Prefer the local file passed in widget, otherwise download remote url to temp file
      File? manufacturerLabelFile = widget.manufacturerLabelImage;
      if (manufacturerLabelFile == null && _manufacturerLabelUrl != null) {
        manufacturerLabelFile = await _downloadToTempFile(_manufacturerLabelUrl!, prefix: 'manufacturer');
      }

      // ---------------- open box exterior/interior ----------------
      File? openBoxExteriorFile;
      if (_openBoxExteriorImageUrl != null && _openBoxExteriorImageUrl!.isNotEmpty) {
        openBoxExteriorFile = await _downloadToTempFile(_openBoxExteriorImageUrl!, prefix: 'openbox_ext');
      }
      File? openBoxInteriorFile;
      if (_openBoxInteriorImageUrl != null && _openBoxInteriorImageUrl!.isNotEmpty) {
        openBoxInteriorFile = await _downloadToTempFile(_openBoxInteriorImageUrl!, prefix: 'openbox_int');
      }

      // ---------------- collect video URLs ----------------
      final List<String> videoUrls = [];
      if (_packageVideoUrl != null && _packageVideoUrl!.isNotEmpty) videoUrls.add(_packageVideoUrl!);
      if (_conditionVideoUrl != null && _conditionVideoUrl!.isNotEmpty) videoUrls.add(_conditionVideoUrl!);
      // You can also include other video hosts/links if available

      // ---------------- pick dimension values ----------------
      final dims = {
        'weight': widget.weight.isNotEmpty ? widget.weight : (_weightValue ?? ''),
        'length': widget.length.isNotEmpty ? widget.length : (_lengthValue ?? ''),
        'height': widget.height.isNotEmpty ? widget.height : (_heightValue ?? ''),
        'width': widget.width.isNotEmpty ? widget.width : (_widthValue ?? ''),
      };

      // ---------------- generate PDF ----------------
      final pdfBytes = await PdfService.generateFinalReportPdf(
        title: 'Final Inspection Report',
        poItems: poItems,
        dimensions: dims,
        hasTestReports: widget.hasTestReports || (_interiorTestReportAnswer?.toLowerCase() == 'yes'),
        exteriorImages: exteriorFiles,
        conditionImages: conditionFiles,
        interiorImage: interiorFile,
        slipImage: slipFile,
        weightImage: weightFile,
        lengthImage: lengthFile,
        widthImage: widthFile,
        heightImage: heightFile,

        // new parameters
        slipIsMatch: _slipIsMatch,
        slipNotes: _slipNotes,
        manufacturerLabelImagePath: manufacturerLabelFile?.path,
        hasAntistatic: _hasAntistatic,
        hasBubbleWrap: _hasBubbleWrap,
        labelsMatch: _labelsMatch,
        openBoxExteriorImage: openBoxExteriorFile,
        openBoxInteriorImage: openBoxInteriorFile,
        openBoxIssues: _openBoxIssues,
        interiorTestReportAnswer: _interiorTestReportAnswer,

        // PO/item + video links
        poNumber: _poNumber,
        itemId: _itemId,
        videoUrls: videoUrls.isNotEmpty ? videoUrls : null,
      );

      await PdfService.saveAndOpenPdf(pdfBytes);

      try {
        // require you have _poNumber and _itemId available in FinalReportPage
        final downloadUrl = await PdfService.saveAndUploadPdf(
          pdfBytes,
          poNumber: _poNumber ?? 'unknown_po',
          itemId: _itemId ?? 'unknown_item',
          filename: 'final_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
          additionalData: {
            'generatedBy': 'inspectorXYZ', // optional
            'hasTestReports': widget.hasTestReports,
            // any other metadata you want to store
          },
        );

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded PDF to storage: $downloadUrl')));
      } catch (e) {
        debugPrint('Upload error: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload PDF: $e')));
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF generated')));
    } catch (e, st) {
      debugPrint('PDF generation error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e')));
    } finally {
      setState(() => _isGeneratingPdf = false);
    }
  }

  // helper to return friendly filename for a URL (or path)
  String _friendlyNameForMedia({File? file, String? url, String fallback = ''}) {
    if (file != null) return file.path.split('/').last;
    if (url != null && url.isNotEmpty) {
      try {
        final uri = Uri.parse(url);
        if (uri.pathSegments.isNotEmpty) return uri.pathSegments.last;
      } catch (_) {
        // fallthrough
      }
      // if parsing fails, don't show entire url — return a fixed label
      return fallback.isNotEmpty ? fallback : 'Uploaded media';
    }
    return '';
  }

  // Video player card updated to support either local File or network URL
  Widget _buildVideoCard({File? file, String? url, String label = 'VIDEO', bool showDisplayName = true}) {
    if (file == null && (url == null || url.isEmpty)) {
      return _buildLabeledLargeCard(null, label, height: 200);
    }
    return _NetworkOrFileVideoCard(
      videoFile: file,
      videoUrl: url,
      label: label,
      displayName: _friendlyNameForMedia(file: file, url: url, fallback: label),
      showDisplayName: showDisplayName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final exteriorMedia = [
      {'label': 'TOP VIEW', 'file': widget.packageImage, 'url': _packageTopUrl},
      {'label': 'BOTTOM VIEW', 'file': widget.packageImage, 'url': _packageBottomUrl},
      {'label': 'LEFT VIEW', 'file': widget.packageImage, 'url': _packageLeftUrl},
      {'label': 'RIGHT VIEW', 'file': widget.packageImage, 'url': _packageRightUrl},
      {'label': 'FRONT VIEW', 'file': widget.packageImage, 'url': _packageFrontUrl},
      {'label': 'BACK VIEW', 'file': widget.packageImage, 'url': _packageBackUrl},
      {'label': 'PACKAGE VIDEO', 'videoFile': widget.packageVideo, 'videoUrl': _packageVideoUrl},
    ];

    final conditionMedia = [
      {'label': 'TOP VIEW', 'file': widget.conditionLineImage, 'url': _condTopUrl},
      {'label': 'BOTTOM VIEW', 'file': widget.conditionLineImage, 'url': _condBottomUrl},
      {'label': 'LEFT VIEW', 'file': widget.conditionLineImage, 'url': _condLeftUrl},
      {'label': 'RIGHT VIEW', 'file': widget.conditionLineImage, 'url': _condRightUrl},
      {'label': 'FRONT VIEW', 'file': widget.conditionLineImage, 'url': _condFrontUrl},
      {'label': 'BACK VIEW', 'file': widget.conditionLineImage, 'url': _condBackUrl},
      {'label': 'OPEN BOX VIDEO', 'videoFile': widget.conditionVideo, 'videoUrl': _conditionVideoUrl},
    ];

    // dimension strings for UI: prefer widget.* then fetched state variables then empty
    final uiWeight = widget.weight.isNotEmpty ? widget.weight : (_weightValue ?? '');
    final uiLength = widget.length.isNotEmpty ? widget.length : (_lengthValue ?? '');
    final uiHeight = widget.height.isNotEmpty ? widget.height : (_heightValue ?? '');
    final uiWidth = widget.width.isNotEmpty ? widget.width : (_widthValue ?? '');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0070C0),
        title: const Text('FINAL REPORT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Generate PDF',
            onPressed: _isGeneratingPdf ? null : _generatePdf,
          ),
        ],
      ),
      body: Column(children: [
        // Step 8 progress bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: StepProgressBar(
            currentStep: 8,
            totalSteps: 8,
            activeColor: const Color(0xFF0070C0),
            inactiveColor: Colors.grey.shade300,
            height: 4,
            spacing: 4,
          ),
        ),

        if (_isGeneratingPdf) const LinearProgressIndicator(minHeight: 4, backgroundColor: Colors.white, color: Color(0xFF0070C0)),

        if (_isFetching)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),

        if (!_isFetching && _fetchError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_fetchError!, style: const TextStyle(color: Colors.red)),
          ),

        // Scrollable content
        if (!_isFetching)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildSectionTitle('RECEIVED PACKAGE IMAGES'),
                _buildMediaGrid(exteriorMedia),
                const SizedBox(height: 20),

                _buildSectionTitle('WEIGHT AND DIMENSIONS'),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _buildDimensionItem('WEIGHT', uiWeight.isNotEmpty ? '$uiWeight lbs' : '—'),
                  _buildDimensionItem('LENGTH', uiLength.isNotEmpty ? '$uiLength in' : '—'),
                  _buildDimensionItem('HEIGHT', uiHeight.isNotEmpty ? '$uiHeight in' : '—'),
                  _buildDimensionItem('WIDTH', uiWidth.isNotEmpty ? '$uiWidth in' : '—'),
                ]),
                const SizedBox(height: 10),
                _buildWeightImagesRow(),
                const SizedBox(height: 20),

                _buildSectionTitle('PACKAGE INTERIOR'),
                _buildLabeledLargeCard(widget.interiorImage ?? null, 'PACKAGE INTERIOR', height: 250, imageUrl: _interiorImageUrl),
                _buildTestReportRow(),
                const SizedBox(height: 20),

                _buildSectionTitle('PACKING SLIP'),
                _slipImageUrls.isNotEmpty
                    ? _buildMediaGrid(_slipImageUrls.map((u) => {
                  'label': 'SLIP',
                  'file': null,
                  'url': u,
                }).toList())
                    : _buildLabeledLargeCard(widget.slipImage, 'PACKING SLIP', height: 250),
                const SizedBox(height: 10),

                // Confirmation + notes
                if (_slipIsMatch != null)
                  Row(
                    children: [
                      const Text('Packing slip matches list? ',
                          style: TextStyle(fontSize: 14, color: Colors.grey)),
                      Text(
                        _slipIsMatch!,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _slipIsMatch == 'YES' ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),

                if (_slipNotes != null && _slipNotes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text('Notes: $_slipNotes',
                        style: const TextStyle(fontSize: 14, color: Colors.black87)),
                  ),

                const SizedBox(height: 20),

                if (_manufacturerLabelUrl != null && _manufacturerLabelUrl!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'MANUFACTURER LABEL',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        _manufacturerLabelUrl!,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // OPEN BOX INSPECTION SECTION
                _buildSectionTitle('OPEN BOX INSPECTION'),

                // Packaging Checklist
                _buildSectionSubTitle('Packaging Checklist'),
                _buildChecklistItem('Antistatic bag present', _hasAntistatic),
                _buildChecklistItem('Bubble wrap present', _hasBubbleWrap),
                _buildChecklistItem('Labels match box exterior', _labelsMatch),

                const SizedBox(height: 16),

                // Side-by-side exterior/interior images
                _buildSectionSubTitle('Box Images'),
                Row(children: [
                  Expanded(
                    child: _RoundedImageCard(
                      imageUrl: _openBoxExteriorImageUrl,
                      label: 'BOX EXTERIOR',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _RoundedImageCard(
                      imageUrl: _openBoxInteriorImageUrl,
                      label: 'BOX INTERIOR',
                    ),
                  ),
                ]),

                const SizedBox(height: 16),

                // Condition images grid
                _buildSectionSubTitle('Condition Images'),
                _buildMediaGrid(conditionMedia),

                const SizedBox(height: 16),

                // Packaging Issues
                if (_openBoxIssues.isNotEmpty) ...[
                  _buildSectionSubTitle('Packaging Issues'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _openBoxIssues.map((issue) => Chip(
                      label: Text(issue),
                      backgroundColor: Colors.grey[200],
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                // PO checklist section
                const SizedBox(height: 30),

                Center(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0070C0), padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    onPressed: () => _showAllDoneDialog(context),
                    child: const Text('Submit Inspection Report', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 30),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _buildChecklistItem(String text, bool isChecked) {
    return ListTile(
      leading: Icon(
        isChecked ? Icons.check_circle : Icons.cancel,
        color: isChecked ? Colors.green : Colors.red,
      ),
      title: Text(text),
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 24,
    );
  }

  // Helper method for section subtitles
  Widget _buildSectionSubTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Color(0xFF003366),
      ),
    ),
  );

  Widget _buildSectionTitle(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
  );

  Widget _buildMediaGrid(List<Map<String, dynamic>> items) {
    List<Widget> rows = [];
    for (var i = 0; i < items.length; i += 2) {
      rows.add(Row(
        children: [
          Expanded(child: _buildMediaCard(items[i])),
          const SizedBox(width: 10),
          if (i + 1 < items.length) Expanded(child: _buildMediaCard(items[i + 1])),
        ],
      ));
      rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }

  Widget _buildMediaCard(Map<String, dynamic> item) {
    if (item.containsKey('videoFile') || item.containsKey('videoUrl')) {
      final File? vf = item['videoFile'] as File?;
      final String? vu = item['videoUrl'] as String?;
      final bool showDisplayName = item.containsKey('showDisplayName') ? (item['showDisplayName'] as bool) : true;

      if ((vf == null) && (vu == null || vu.isEmpty)) {
        return _buildLabeledLargeCard(null, item['label'], height: 200);
      }
      return _buildVideoCard(file: vf, url: vu, label: item['label'], showDisplayName: showDisplayName);
    }

    final File? f = item['file'] as File?;
    final String? u = item['url'] as String?;
    return _RoundedImageCard(imageFile: f, imageUrl: u, label: item['label']);
  }

  Widget _buildDimensionItem(String t, String v) => Column(children: [
    Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
    const SizedBox(height: 4),
    Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
  ]);

  Widget _buildWeightImagesRow() {
    // Create a list of weight/dimension media items similar to exteriorMedia
    final weightMedia = [
      {'label': 'WEIGHT', 'file': widget.weightImage, 'url': _weightImageUrl},
      {'label': 'LENGTH', 'file': widget.lenghtImage, 'url': _lengthImageUrl},
      {'label': 'WIDTH', 'file': widget.widthImage, 'url': _widthImageUrl},
      {'label': 'HEIGHT', 'file': widget.heightImage, 'url': _heightImageUrl},
    ];

    // Use the same grid layout as package images
    return _buildMediaGrid(weightMedia);
  }

  Widget _buildLabeledLargeCard(File? img, String label, {double height = 250, String? imageUrl}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: height,
            color: Colors.grey[200],
            child: img != null
                ? Image.file(img, fit: BoxFit.cover)
                : (imageUrl != null ? Image.network(imageUrl, fit: BoxFit.cover) : const Center(child: Icon(Icons.add, size: 48, color: Colors.grey))),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0070C0))),
    ]);
  }

  Widget _buildTestReportRow() => Row(children: [
    const Text('Does this package contain test reports?', style: TextStyle(fontSize: 14, color: Colors.grey)),
    const SizedBox(width: 8),
    Text((widget.hasTestReports || (_interiorTestReportAnswer?.toLowerCase() == 'yes')) ? 'YES' : 'NO',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
  ]);

  void _showAllDoneDialog(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, size: 64, color: Color(0xFF0070C0)),
          const SizedBox(height: 16),
          const Text('All done!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Your report has been sent successfully.'),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0070C0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12)),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(ctx).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomePage()), (route) => false);
            },
            child: const Text('HOME', style: TextStyle(color: Colors.white)),
          )
        ]),
      ),
    );
  }
}

/// Image card widget (supports either local File or remote URL)
class _RoundedImageCard extends StatelessWidget {
  final File? imageFile;
  final String? imageUrl;
  final String label;
  const _RoundedImageCard({this.imageFile, this.imageUrl, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 200,
            color: Colors.grey[200],
            child: imageFile != null
                ? Image.file(imageFile!, fit: BoxFit.cover)
                : (imageUrl != null ? Image.network(imageUrl!, fit: BoxFit.cover) : const Center(child: Icon(Icons.add, size: 48, color: Colors.grey))),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0070C0))),
    ]);
  }
}

/// Video player with either a local File or network URL — displays friendly filename instead of raw URL
class _NetworkOrFileVideoCard extends StatefulWidget {
  final File? videoFile;
  final String? videoUrl;
  final String label;
  final String? displayName; // friendly text to show below video (filename or label)
  final bool showDisplayName;

  const _NetworkOrFileVideoCard({
    this.videoFile,
    this.videoUrl,
    required this.label,
    this.displayName,
    this.showDisplayName = true,
  });

  @override
  _NetworkOrFileVideoCardState createState() => _NetworkOrFileVideoCardState();
}

class _NetworkOrFileVideoCardState extends State<_NetworkOrFileVideoCard> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void didUpdateWidget(covariant _NetworkOrFileVideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoFile?.path != widget.videoFile?.path || oldWidget.videoUrl != widget.videoUrl) {
      _controller?.dispose();
      _ready = false;
      _initController();
    }
  }

  Future<void> _initController() async {
    try {
      if (widget.videoFile != null) {
        _controller = VideoPlayerController.file(widget.videoFile!);
      } else if (widget.videoUrl != null && widget.videoUrl!.isNotEmpty) {
        _controller = VideoPlayerController.network(widget.videoUrl!);
      } else {
        return;
      }
      await _controller!.initialize();
      setState(() => _ready = true);
      _controller!.setLooping(true);
    } catch (e) {
      debugPrint('Video init failed: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.displayName ?? (widget.videoFile != null ? widget.videoFile!.path.split('/').last : widget.videoUrl ?? '');

    return Column(children: [
      if (!_ready)
        Container(height: 200, alignment: Alignment.center, child: const CircularProgressIndicator())
      else
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: GestureDetector(
                onTap: () => setState(() {
                  _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
                }),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_controller!),
                    if (!_controller!.value.isPlaying) const Icon(Icons.play_circle_fill, size: 50, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ),
        ),
      const SizedBox(height: 8),
      // Show friendly filename or a short label only when showDisplayName is true
      if (widget.showDisplayName && displayName.isNotEmpty)
        Text(displayName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0070C0))),
      const SizedBox(height: 10),
    ]);
  }
}
