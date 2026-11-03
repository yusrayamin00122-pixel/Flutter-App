import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PdfMasterApp());
}

class PdfMasterApp extends StatelessWidget {
  const PdfMasterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Master',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  String? _activePdfPath;

  void _openInViewer(String filePath) {
    setState(() {
      _activePdfPath = filePath;
      _currentIndex = 1; // Switch to Viewer tab
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      ToolsGridScreen(onFileReady: _openInViewer),
      PdfViewerScreen(
        filePath: _activePdfPath,
        onPickNew: () async {
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['pdf'],
          );
          if (result != null && result.files.single.path != null) {
            _openInViewer(result.files.single.path!);
          }
        },
      ),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_customize_outlined),
            selectedIcon: Icon(Icons.dashboard_customize),
            label: 'Tools',
          ),
          NavigationDestination(
            icon: Icon(Icons.picture_as_pdf_outlined),
            selectedIcon: Icon(Icons.picture_as_pdf),
            label: 'Viewer',
          ),
        ],
      ),
    );
  }
}

// ==========================================
// TOOLS DASHBOARD SCREEN
// ==========================================
class ToolsGridScreen extends StatefulWidget {
  final Function(String path) onFileReady;
  const ToolsGridScreen({super.key, required this.onFileReady});

  @override
  State<ToolsGridScreen> createState() => _ToolsGridScreenState();
}

class _ToolsGridScreenState extends State<ToolsGridScreen> {
  bool _isLoading = false;
  String _statusMessage = '';

  Future<String> _getAppDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  void _showLoading(String message) {
    setState(() {
      _isLoading = true;
      _statusMessage = message;
    });
  }

  void _hideLoading() {
    setState(() {
      _isLoading = false;
      _statusMessage = '';
    });
  }

  // --- 1. MERGE PDFS ---
  Future<void> _mergePdfs() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.length < 2) {
      _snack('Select at least 2 PDF files to merge.');
      return;
    }

    _showLoading('Merging documents...');
    try {
      final PdfDocument outputDoc = PdfDocument();
      for (final file in result.files) {
        if (file.path != null) {
          final bytes = await File(file.path!).readAsBytes();
          final loadedDoc = PdfDocument(inputBytes: bytes);
          for (int i = 0; i < loadedDoc.pages.count; i++) {
            outputDoc.pages.add().graphics.drawPdfTemplate(
                  loadedDoc.pages[i].createTemplate(),
                  Offset.zero,
                );
          }
          loadedDoc.dispose();
        }
      }
      final outBytes = await outputDoc.save();
      outputDoc.dispose();

      final outPath = '${await _getAppDir()}/merged_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await File(outPath).writeAsBytes(outBytes);
      _hideLoading();
      _showResultDialog(outPath, 'PDFs merged successfully!');
    } catch (e) {
      _hideLoading();
      _snack('Error merging PDFs: $e');
    }
  }

  // --- 2. IMAGES TO PDF ---
  Future<void> _imagesToPdf() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.isEmpty) return;

    _showLoading('Converting images to PDF...');
    try {
      final PdfDocument doc = PdfDocument();
      doc.pageSettings.margins.all = 0;

      for (final img in pickedFiles) {
        final bytes = await File(img.path).readAsBytes();
        final PdfBitmap bitmap = PdfBitmap(bytes);
        final PdfPage page = doc.pages.add();
        page.graphics.drawImage(
          bitmap,
          Rect.fromLTWH(0, 0, page.size.width, page.size.height),
        );
      }

      final outBytes = await doc.save();
      doc.dispose();

      final outPath = '${await _getAppDir()}/photos_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await File(outPath).writeAsBytes(outBytes);
      _hideLoading();
      _showResultDialog(outPath, 'Images converted to PDF!');
    } catch (e) {
      _hideLoading();
      _snack('Error converting images: $e');
    }
  }

  // --- 3. SPLIT PDF ---
  Future<void> _splitPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.single.path == null) return;

    _showLoading('Extracting pages...');
    try {
      final bytes = await File(result.files.single.path!).readAsBytes();
      final loadedDoc = PdfDocument(inputBytes: bytes);
      final count = loadedDoc.pages.count;

      if (count <= 1) {
        _hideLoading();
        loadedDoc.dispose();
        _snack('PDF contains only 1 page.');
        return;
      }

      // Extract page 1 as a separate document
      final singleDoc = PdfDocument();
      singleDoc.pages.add().graphics.drawPdfTemplate(
            loadedDoc.pages[0].createTemplate(),
            Offset.zero,
          );
      final outBytes = await singleDoc.save();
      singleDoc.dispose();
      loadedDoc.dispose();

      final outPath = '${await _getAppDir()}/page_1_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await File(outPath).writeAsBytes(outBytes);
      _hideLoading();
      _showResultDialog(outPath, 'Extracted page 1 out of $count pages!');
    } catch (e) {
      _hideLoading();
      _snack('Error splitting PDF: $e');
    }
  }

  // --- 4. WATERMARK PDF ---
  Future<void> _watermarkPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.single.path == null) return;

    final controller = TextEditingController(text: 'CONFIDENTIAL');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Watermark Text'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Text')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Apply')),
        ],
      ),
    );

    if (text == null || text.trim().isEmpty) return;

    _showLoading('Applying watermark...');
    try {
      final bytes = await File(result.files.single.path!).readAsBytes();
      final doc = PdfDocument(inputBytes: bytes);
      final font = PdfStandardFont(PdfFontFamily.helvetica, 45, style: PdfFontStyle.bold);
      final brush = PdfSolidBrush(PdfColor(200, 0, 0, 80));

      for (int i = 0; i < doc.pages.count; i++) {
        final page = doc.pages[i];
        final size = page.size;
        final graphics = page.graphics;
        graphics.save();
        graphics.translateTransform(size.width / 4, size.height / 2);
        graphics.rotateTransform(-40);
        graphics.drawString(text, font, brush: brush);
        graphics.restore();
      }

      final outBytes = await doc.save();
      doc.dispose();

      final outPath = '${await _getAppDir()}/watermarked_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await File(outPath).writeAsBytes(outBytes);
      _hideLoading();
      _showResultDialog(outPath, 'Watermark applied!');
    } catch (e) {
      _hideLoading();
      _snack('Error applying watermark: $e');
    }
  }

  // --- 5. EXTRACT TEXT ---
  Future<void> _extractText() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.single.path == null) return;

    _showLoading('Extracting text content...');
    try {
      final bytes = await File(result.files.single.path!).readAsBytes();
      final doc = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(doc);
      final extracted = extractor.extractText();
      doc.dispose();
      _hideLoading();

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Extracted Text'),
          content: SingleChildScrollView(child: SelectableText(extracted.isEmpty ? 'No text found in PDF.' : extracted)),
          actions: [
            TextButton(
              onPressed: () {
                Share.share(extracted);
                Navigator.pop(ctx);
              },
              child: const Text('Share Text'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      _hideLoading();
      _snack('Error extracting text: $e');
    }
  }

  void _showResultDialog(String path, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text('Saved to:\n$path'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Share.shareXFiles([XFile(path)]);
            },
            child: const Text('Share'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onFileReady(path);
            },
            child: const Text('Open in Viewer'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Master Workstation'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              children: [
                _ToolCard(
                  icon: Icons.merge_type_rounded,
                  color: Colors.deepPurple,
                  title: 'Merge PDF',
                  subtitle: 'Combine files',
                  onTap: _mergePdfs,
                ),
                _ToolCard(
                  icon: Icons.call_split_rounded,
                  color: Colors.orange,
                  title: 'Split PDF',
                  subtitle: 'Extract page',
                  onTap: _splitPdf,
                ),
                _ToolCard(
                  icon: Icons.photo_library_outlined,
                  color: Colors.blue,
                  title: 'Images to PDF',
                  subtitle: 'Photos to doc',
                  onTap: _imagesToPdf,
                ),
                _ToolCard(
                  icon: Icons.branding_watermark_outlined,
                  color: Colors.redAccent,
                  title: 'Watermark',
                  subtitle: 'Add stamp',
                  onTap: _watermarkPdf,
                ),
                _ToolCard(
                  icon: Icons.text_snippet_outlined,
                  color: Colors.teal,
                  title: 'Extract Text',
                  subtitle: 'Read words',
                  onTap: _extractText,
                ),
                _ToolCard(
                  icon: Icons.visibility_outlined,
                  color: Colors.indigo,
                  title: 'Open Reader',
                  subtitle: 'View any file',
                  onTap: () async {
                    final res = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['pdf'],
                    );
                    if (res != null && res.files.single.path != null) {
                      widget.onFileReady(res.files.single.path!);
                    }
                  },
                ),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black45,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(_statusMessage),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: color.withOpacity(0.15),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// BUILT-IN SMART PDF VIEWER SCREEN
// ==========================================
class PdfViewerScreen extends StatefulWidget {
  final String? filePath;
  final VoidCallback onPickNew;

  const PdfViewerScreen({super.key, required this.filePath, required this.onPickNew});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfViewerController _pdfViewerController = PdfViewerController();

  @override
  Widget build(BuildContext context) {
    if (widget.filePath == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PDF Reader')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.picture_as_pdf_outlined, size: 80, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text('No document loaded', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.file_open),
                label: const Text('Choose a PDF'),
                onPressed: widget.onPickNew,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.filePath!.split('/').last, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.zoom_in),
            onPressed: () => _pdfViewerController.zoomLevel = _pdfViewerController.zoomLevel + 0.25,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => Share.shareXFiles([XFile(widget.filePath!)]),
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: widget.onPickNew,
          ),
        ],
      ),
      body: SfPdfViewer.file(
        File(widget.filePath!),
        controller: _pdfViewerController,
      ),
    );
  }
}
