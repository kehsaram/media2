// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// Use dart:ui_web for platformViewRegistry on Flutter web
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

class PlatformWebImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final double borderRadius;

  const PlatformWebImage({
    super.key,
    required this.imageUrl,
    required this.fit,
    this.width,
    this.height,
    this.borderRadius = 0,
  });

  @override
  State<PlatformWebImage> createState() => _PlatformWebImageState();
}

class _PlatformWebImageState extends State<PlatformWebImage> {
  late String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'web-image-${DateTime.now().microsecondsSinceEpoch}-${widget.imageUrl.hashCode}';
    
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      final img = html.ImageElement();
      img.src = widget.imageUrl;
      img.style.width = '100%';
      img.style.height = '100%';
      img.style.borderRadius = '${widget.borderRadius}px';
      img.style.pointerEvents = 'none'; // Allow clicks to pass through to Flutter
      
      String objectFit = 'cover';
      switch (widget.fit) {
        case BoxFit.contain:
          objectFit = 'contain';
          break;
        case BoxFit.fill:
          objectFit = 'fill';
          break;
        case BoxFit.fitHeight:
        case BoxFit.fitWidth:
        case BoxFit.none:
        case BoxFit.scaleDown:
          objectFit = 'none';
          break;
        case BoxFit.cover:
        default:
          objectFit = 'cover';
          break;
      }
      img.style.objectFit = objectFit;
      
      return img;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: HtmlElementView(viewType: _viewId),
    );
  }
}
