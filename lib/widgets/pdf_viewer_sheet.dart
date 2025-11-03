import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

class PdfViewerSheet extends StatefulWidget {
  final String url;
  final String? title;

  const PdfViewerSheet({super.key, required this.url, this.title});

  @override
  State<PdfViewerSheet> createState() => _PdfViewerSheetState();
}

class _PdfViewerSheetState extends State<PdfViewerSheet> {
  PdfControllerPinch? _pdfController;
  WebViewController? _webController;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted);
      final viewerUrl = Uri.encodeComponent(widget.url);
      final googleViewer =
          'https://docs.google.com/gview?embedded=1&url=$viewerUrl';
      c.loadRequest(Uri.parse(googleViewer));
      _webController = c;
    } else {
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openData(_loadBytes(widget.url)),
      );
    }
  }

  static Future<Uint8List> _loadBytes(String url) async {
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) {
      return resp.bodyBytes;
    }
    throw Exception('Failed to load PDF');
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  widget.title ?? 'PDF',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: kIsWeb
                ? WebViewWidget(controller: _webController!)
                : PdfViewPinch(
                    controller: _pdfController!,
                    backgroundDecoration: const BoxDecoration(
                      color: Colors.black,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
