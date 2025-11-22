import 'package:flutter/material.dart';
import 'web_image_stub.dart' if (dart.library.html) 'web_image_web.dart';

class WebImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final double borderRadius;

  const WebImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius = 0,
  });

  @override
  Widget build(BuildContext context) {
    return PlatformWebImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}
