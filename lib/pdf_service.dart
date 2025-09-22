// pdf_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;


class PdfService {
  /// Generates the final inspection report PDF.
  ///
  /// New optional label params:
  /// - exteriorImageLabels: labels to show for exterior images (same order as exteriorImages)
  /// - conditionImageLabels: labels to show for condition images (same order as conditionImages)
  /// - videoLabels: labels to show for each video URL (same order as videoUrls)
  static Future<Uint8List> generateFinalReportPdf({
    required String title,
    required List<Map<String, dynamic>> poItems,
    required Map<String, String> dimensions,
    required bool hasTestReports,
    File? interiorImage,
    File? slipImage,
    File? weightImage,
    File? lengthImage,
    File? widthImage,
    File? heightImage,
    List<File>? exteriorImages,
    List<File>? conditionImages,
    // New parameters for additional data
    String? slipIsMatch,
    String? slipNotes,
    String? manufacturerLabelImagePath,
    bool? hasAntistatic,
    bool? hasBubbleWrap,
    bool? labelsMatch,
    File? openBoxExteriorImage,
    File? openBoxInteriorImage,
    List<String>? openBoxIssues,
    String? interiorTestReportAnswer,
    // NEW: PO/item and video urls
    String? poNumber,
    String? itemId,
    List<String>? videoUrls,
    // NEW: optional labels
    List<String>? exteriorImageLabels,
    List<String>? conditionImageLabels,
    List<String>? videoLabels,
  }) async {
    final pdf = pw.Document();

    // ---------------- Cover Page ----------------
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  title.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  "FINAL INSPECTION REPORT",
                  style: pw.TextStyle(fontSize: 20, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 40),

                // Generated on + PO & Item info
                pw.Text(
                  'Generated on: ${DateTime.now().toString().split(".").first}',
                  style: pw.TextStyle(fontSize: 14, color: PdfColors.grey),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'PO: ${poNumber ?? '-'}    Item: ${itemId ?? '-'}',
                  style: pw.TextStyle(fontSize: 14, color: PdfColors.grey900),
                ),
              ],
            ),
          );
        },
      ),
    );

    // ---------------- Package Images ----------------
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        footer: _buildFooter,
        build: (pw.Context context) {
          return [
            _buildSectionHeader('RECEIVED PACKAGE IMAGES'),
            pw.SizedBox(height: 8),
            _buildImageGridWithLabels(
              exteriorImages ?? [],
              exteriorImageLabels,
              defaultLabels: ['TOP VIEW', 'BOTTOM VIEW', 'LEFT VIEW', 'RIGHT VIEW', 'FRONT VIEW', 'BACK VIEW'],
              context: context,
            ),
          ];
        },
      ),
    );

    // ---------------- Weight + Dimensions ----------------
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        footer: _buildFooter,
        build: (pw.Context context) {
          return [
            _buildSectionHeader('WEIGHT AND DIMENSIONS'),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(
                  children: [
                    _buildDimensionCell('WEIGHT', dimensions['weight'] ?? '—'),
                    _buildDimensionCell('LENGTH', dimensions['length'] ?? '—'),
                    _buildDimensionCell('WIDTH', dimensions['width'] ?? '—'),
                    _buildDimensionCell('HEIGHT', dimensions['height'] ?? '—'),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Wrap(
              spacing: 15,
              runSpacing: 15,
              children: [
                _buildImageCard(weightImage, 'WEIGHT PICTURE', context),
                _buildImageCard(lengthImage, 'LENGTH PICTURE', context),
                _buildImageCard(widthImage, 'WIDTH PICTURE', context),
                _buildImageCard(heightImage, 'HEIGHT PICTURE', context),
              ],
            ),
          ];
        },
      ),
    );

    // ---------------- Interior ----------------
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        footer: _buildFooter,
        build: (pw.Context context) {
          return [
            _buildSectionHeader('PACKAGE INTERIOR'),
            pw.SizedBox(height: 8),
            if (interiorImage != null) _buildImageCard(interiorImage, 'PACKAGE INTERIOR', context),
            pw.SizedBox(height: 20),
            pw.Text(
              'Contains test reports: ${hasTestReports || (interiorTestReportAnswer?.toLowerCase() == 'yes') ? 'YES' : 'NO'}',
              style: pw.TextStyle(fontSize: 14, color: PdfColors.black),
            ),
          ];
        },
      ),
    );

    // ---------------- Packing Slip ----------------
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        footer: _buildFooter,
        build: (pw.Context context) {
          return [
            _buildSectionHeader('PACKING SLIP'),
            pw.SizedBox(height: 8),
            if (slipImage != null) _buildImageCard(slipImage, 'PACKING SLIP', context),
            if (slipIsMatch != null) pw.SizedBox(height: 10),
            if (slipIsMatch != null)
              pw.Row(
                children: [
                  pw.Text(
                    'Packing slip matches list: ',
                    style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
                  ),
                  pw.Text(
                    slipIsMatch!,
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: slipIsMatch == 'YES' ? PdfColors.green : PdfColors.red,
                    ),
                  ),
                ],
              ),
            if (slipNotes != null && slipNotes!.isNotEmpty) pw.SizedBox(height: 8),
            if (slipNotes != null && slipNotes!.isNotEmpty)
              pw.Text(
                'Notes: $slipNotes',
                style: pw.TextStyle(fontSize: 14, color: PdfColors.black),
              ),
          ];
        },
      ),
    );

    // ---------------- Manufacturer Label ----------------
    if (manufacturerLabelImagePath != null) {
      try {
        final File mfile = File(manufacturerLabelImagePath);
        if (mfile.existsSync()) {
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              footer: _buildFooter,
              build: (pw.Context context) {
                return [
                  _buildSectionHeader('MANUFACTURER LABEL'),
                  pw.SizedBox(height: 10),
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    child: pw.Image(
                      pw.MemoryImage(mfile.readAsBytesSync()),
                      height: 300,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ];
              },
            ),
          );
        }
      } catch (_) {
        // ignore read errors, continue
      }
    }

    // ---------------- Videos (links) ----------------
    if (videoUrls != null && videoUrls.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          footer: _buildFooter,
          build: (pw.Context context) {
            return [
              _buildSectionHeader('VIDEOS'),
              pw.SizedBox(height: 8),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: List.generate(videoUrls.length, (i) {
                  final u = videoUrls[i];
                  final label = (videoLabels != null && i < videoLabels.length && videoLabels[i].trim().isNotEmpty)
                      ? videoLabels[i]
                      : 'VIDEO ${i + 1}';
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(label, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                        pw.SizedBox(height: 4),
                        pw.UrlLink(
                          destination: u,
                          child: pw.Text(
                            u,
                            style: pw.TextStyle(
                              fontSize: 12,
                              decoration: pw.TextDecoration.underline,
                              color: PdfColors.blue900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ];
          },
        ),
      );
    }

    // ---------------- Open Box Inspection ----------------
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        footer: _buildFooter,
        build: (pw.Context context) {
          return [
            _buildSectionHeader('OPEN BOX INSPECTION'),
            pw.SizedBox(height: 10),
            _buildSectionSubTitle('Packaging Checklist'),
            _buildChecklistItem('Antistatic bag present', hasAntistatic ?? false),
            pw.SizedBox(height: 6),
            _buildChecklistItem('Bubble wrap present', hasBubbleWrap ?? false),
            pw.SizedBox(height: 6),
            _buildChecklistItem('Labels match box exterior', labelsMatch ?? false),
            pw.SizedBox(height: 16),
            _buildSectionSubTitle('Box Images'),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (openBoxExteriorImage != null)
                  pw.Expanded(child: _buildImageCard(openBoxExteriorImage, 'BOX EXTERIOR', context)),
                if (openBoxInteriorImage != null) pw.SizedBox(width: 12),
                if (openBoxInteriorImage != null)
                  pw.Expanded(child: _buildImageCard(openBoxInteriorImage, 'BOX INTERIOR', context)),
              ],
            ),
            if (openBoxIssues != null && openBoxIssues.isNotEmpty) pw.SizedBox(height: 16),
            if (openBoxIssues != null && openBoxIssues.isNotEmpty) _buildSectionSubTitle('Packaging Issues'),
            if (openBoxIssues != null && openBoxIssues.isNotEmpty)
              pw.Wrap(
                spacing: 8,
                runSpacing: 4,
                children: openBoxIssues.map((issue) {
                  return pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius: pw.BorderRadius.circular(16),
                    ),
                    child: pw.Text(
                      issue,
                      style: pw.TextStyle(fontSize: 12, color: PdfColors.black),
                    ),
                  );
                }).toList(),
              ),
          ];
        },
      ),
    );

    // ---------------- Condition of Line Items ----------------
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        footer: _buildFooter,
        build: (pw.Context context) {
          return [
            _buildSectionHeader('CONDITION OF LINE ITEMS'),
            pw.SizedBox(height: 8),
            _buildImageGridWithLabels(
              conditionImages ?? [],
              conditionImageLabels,
              defaultLabels: ['TOP VIEW', 'BOTTOM VIEW', 'LEFT VIEW', 'RIGHT VIEW', 'FRONT VIEW', 'BACK VIEW'],
              context: context,
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  // ---------------------- HELPERS ----------------------

  static pw.Widget _buildSectionHeader(String title) {
    return pw.Container(
      width: double.infinity,
      color: PdfColors.blue900,
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 16,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  static pw.Widget _buildSectionSubTitle(String title) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blue900,
        ),
      ),
    );
  }

  static pw.Widget _buildImageCard(File? image, String label, pw.Context context) {
    if (image == null) return pw.SizedBox();

    return pw.Container(
      width: 200,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Image(
              pw.MemoryImage(image.readAsBytesSync()),
              height: 150,
              fit: pw.BoxFit.cover,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            label,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            ),
          ),
        ],
      ),
    );
  }

  /// Build grid of images with optional labels.
  /// If labels is null, uses defaultLabels (repeats or truncates as necessary).
  static pw.Widget _buildImageGridWithLabels(
      List<File> images,
      List<String>? labels, {
        required List<String> defaultLabels,
        required pw.Context context,
      }) {
    if (images.isEmpty) return pw.Text('No images available');

    // Prepare labels list that matches images length
    final int n = images.length;
    final List<String> finalLabels = List<String>.generate(n, (i) {
      if (labels != null && i < labels.length && labels[i].trim().isNotEmpty) {
        return labels[i];
      }
      if (i < defaultLabels.length) return defaultLabels[i];
      return 'View ${i + 1}';
    });

    return pw.Wrap(
      spacing: 15,
      runSpacing: 15,
      children: List.generate(images.length, (i) {
        return _buildImageCard(images[i], finalLabels[i], context);
      }),
    );
  }

  static pw.Widget _buildDimensionCell(String title, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      alignment: pw.Alignment.center,
      child: pw.Column(
        children: [
          pw.Text(title,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 12,
                color: PdfColors.grey700,
              )),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildChecklistItem(String text, bool isChecked) {
    return pw.Row(
      children: [
        isChecked
            ? pw.Icon(pw.IconData(0xe5ca), size: 16, color: PdfColors.green)
            : pw.Icon(pw.IconData(0xe5cd), size: 16, color: PdfColors.red),
        pw.SizedBox(width: 8),
        pw.Expanded(child: pw.Text(text, style: pw.TextStyle(fontSize: 12))),
      ],
    );
  }




// Example helpers: put inside your PdfService class or a new StorageService class.

  /// Upload PDF bytes to Firebase Storage and return the download URL.
  /// path structure used: final_reports/{poNumber}/{itemId}/{filename}
  static Future<String> uploadPdfToStorage(
      Uint8List bytes, {
        required String poNumber,
        required String itemId,
        String? filename,
        firebase_storage.FirebaseStorage? storageInstance,
      }) async {
    // Ensure Firebase initialized in caller
    try {
      final storage = storageInstance ?? firebase_storage.FirebaseStorage.instance;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final fname = filename ?? 'final_report_$ts.pdf';
      final path = 'final_reports/$poNumber/$itemId/$fname';
      final ref = storage.ref().child(path);

      final metadata = firebase_storage.SettableMetadata(
        contentType: 'application/pdf',
      );

      // Upload the bytes
      final uploadTask = ref.putData(bytes, metadata);
      final snapshot = await uploadTask.whenComplete(() {});

      // Get download URL
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      // rethrow for caller to handle/log
      throw Exception('Storage upload failed: $e');
    }
  }

  /// Save a Firestore document containing the PDF metadata and download URL.
  /// doc path used: purchase_orders/{poNumber}/{itemId}_inspection/final_report
  static Future<void> savePdfRecordToFirestore({
    required String downloadUrl,
    required String poNumber,
    required String itemId,
    String? filename,
    Map<String, dynamic>? additionalData,
    FirebaseFirestore? firestoreInstance,
  }) async {
    try {
      final firestore = firestoreInstance ?? FirebaseFirestore.instance;
      final docRef = firestore
          .collection('purchase_orders')
          .doc(poNumber)
          .collection('${itemId}_inspection')
          .doc('final_report');

      final payload = <String, dynamic>{
        'url': downloadUrl,
        'filename': filename ?? downloadUrl.split('/').last,
        'uploadedAt': FieldValue.serverTimestamp(),
        ...?additionalData,
      };

      await docRef.set(payload, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to write Firestore record: $e');
    }
  }

  /// Convenience: upload bytes then write Firestore record, return download URL.
  static Future<String> saveAndUploadPdf(
      Uint8List bytes, {
        required String poNumber,
        required String itemId,
        String? filename,
        Map<String, dynamic>? additionalData,
      }) async {
    // ensure Firebase initialized by caller
    final downloadUrl = await uploadPdfToStorage(
      bytes,
      poNumber: poNumber,
      itemId: itemId,
      filename: filename,
    );

    await savePdfRecordToFirestore(
      downloadUrl: downloadUrl,
      poNumber: poNumber,
      itemId: itemId,
      filename: filename,
      additionalData: additionalData,
    );

    return downloadUrl;
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        "Page ${context.pageNumber} of ${context.pagesCount}",
        style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
      ),
    );
  }

  static Future<void> saveAndOpenPdf(Uint8List bytes) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/final_report.pdf');
    await file.writeAsBytes(bytes);
    OpenFile.open(file.path);
  }
}
