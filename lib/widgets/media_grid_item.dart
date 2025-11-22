import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kDebugMode;
import '../services/media_storage_service.dart';
import 'video_player_sheet.dart';
import 'pdf_viewer_sheet.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'web_image.dart';

class MediaGridItem extends StatefulWidget {
  final Map<String, dynamic> mediaData;
  final VoidCallback onDelete;

  const MediaGridItem({
    super.key,
    required this.mediaData,
    required this.onDelete,
  });

  @override
  State<MediaGridItem> createState() => _MediaGridItemState();
}

class _MediaGridItemState extends State<MediaGridItem> {
  late final Future<String?> _resolvedUrlFuture;
  late final Future<Uint8List?> _thumbBytesFuture;
  String _lastByteSource = '';
  String _lastUrlSource = '';

  Widget _imageFromUrl(
    String primary, {
    String? alt,
    BoxFit fit = BoxFit.cover,
  }) {
    if (kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: WebImage(
          imageUrl: primary,
          fit: fit,
        ),
      );
    }

    FutureBuilder<Uint8List?> buildBytesFallback(String url) {
      return FutureBuilder<Uint8List?>(
        future: _loadBytesForUrl(url),
        builder: (context, snap) {
          final b = snap.data;
          if (b != null && b.isNotEmpty) {
            return Image.memory(b, fit: fit);
          }
          return _fallbackTile('image');
        },
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        primary,
        fit: fit,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: Colors.grey[300],
            child: const Center(child: CircularProgressIndicator()),
          );
        },
        errorBuilder: (context, _, __) {
          if (kDebugMode) {
            // ignore: avoid_print
            print(
              '[MediaGridItem:image] URL failed primary=${primary.substring(0, primary.length > 60 ? 60 : primary.length)}... alt=${alt ?? ''}',
            );
          }
          // Try the alternate URL once if provided
          if (alt != null && alt.isNotEmpty && alt != primary) {
            return Image.network(
              alt,
              fit: fit,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: Colors.grey[300],
                  child: const Center(child: CircularProgressIndicator()),
                );
              },
              errorBuilder: (context, _, __) {
                if (kDebugMode) {
                  // ignore: avoid_print
                  print('[MediaGridItem:image] ALT URL failed');
                }
                final tryUrl = alt.isNotEmpty ? alt : primary;
                return buildBytesFallback(tryUrl);
              },
            );
          }
          return buildBytesFallback(primary);
        },
      ),
    );
  }

  Future<Uint8List?> _loadBytesForUrl(String url) async {
    final sdkBytes = await _storageFetchBytes(url);
    if (sdkBytes != null && sdkBytes.isNotEmpty) {
      _lastByteSource = 'storage-fetch-bytes';
      return sdkBytes;
    }
    final httpBytes = await _httpFetchBytes(url);
    if (httpBytes != null && httpBytes.isNotEmpty) {
      _lastByteSource = 'http-bytes';
      return httpBytes;
    }
    return null;
  }

  Future<Uint8List?> _httpFetchBytes(String url) async {
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[MediaGridItem:image] HTTP bytes fallback OK');
        }
        return resp.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  @override
  void initState() {
    super.initState();
    // Add a soft timeout so tiles don't spin forever on web if a URL is bad/CORSed
    _resolvedUrlFuture = _resolveDownloadUrl().timeout(
      const Duration(seconds: 10),
      onTimeout: () async {
        final hint = _urlHintFromDoc();
        return hint?.isNotEmpty == true ? hint : null;
      },
    );
    _thumbBytesFuture = _tryLoadThumbBytes().timeout(
      const Duration(seconds: 8),
      onTimeout: () => null,
    );
  }

  Future<String?> _resolveDownloadUrl() async {
    final docHint = _urlHintFromDoc();

    Future<String?> tryDocUrl({bool allowRawFallback = false}) async {
      if (docHint == null || docHint.isEmpty) return null;
      final uri = Uri.tryParse(docHint);
      final host = uri?.host.toLowerCase() ?? '';
      final needsRehydrate = host.contains('storage.cloud.google.com') ||
          (host.contains('storage.googleapis.com') &&
              !host.contains('firebasestorage'));

      if (needsRehydrate) {
        final hydrated = await _rehydrateFromGcsUrl(docHint);
        if (hydrated != null && hydrated.isNotEmpty) {
          _lastUrlSource = 'rehydrated-doc-url';
          return hydrated;
        }
        if (!allowRawFallback) {
          return null;
        }
      }

      _lastUrlSource = 'doc-url';
      return docHint;
    }

    if (kIsWeb) {
      final docUrl = await tryDocUrl();
      if (docUrl != null) {
        return docUrl;
      }
    }

    void log(String msg) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[MediaGridItem:url] ${widget.mediaData['fileName']}: $msg');
      }
    }

    // Prefer a fresh URL from storagePath first (handles stale tokens), then use saved URLs
    final mediaType = widget.mediaData['mediaType'] as String?;
    final storagePath = widget.mediaData['storagePath'] ?? _guessStoragePath();
    if (storagePath is String && storagePath.isNotEmpty) {
      try {
        log('resolving fresh from storagePath: $storagePath');
        final fresh = await FirebaseStorage.instance
            .ref(storagePath)
            .getDownloadURL();
        if (fresh.isNotEmpty) {
          _lastUrlSource = 'storagePath-url';
          return fresh;
        }
      } catch (_) {
        log('failed to resolve fresh from storagePath');
      }
    }

    // Fallback to saved URLs, but try to refresh them first via refFromURL
    if (mediaType == 'image') {
      final url = widget.mediaData['downloadUrl'];
      if (url is String && url.isNotEmpty) {
        try {
          log('refreshing from saved downloadUrl (image)');
          final fresh = await FirebaseStorage.instance
              .refFromURL(url)
              .getDownloadURL();
          if (fresh.isNotEmpty) {
            _lastUrlSource = 'refFromURL(downloadUrl)-url';
            return fresh;
          }
        } catch (_) {
          // Handle older GCS console URLs (storage.googleapis.com / storage.cloud.google.com)
          final rehydrated = await _rehydrateFromGcsUrl(url);
          if (rehydrated != null && rehydrated.isNotEmpty) {
            _lastUrlSource = 'rehydrated-gcs-download-url';
            return rehydrated;
          }
        }
        log('using saved downloadUrl (image)');
        _lastUrlSource = 'saved-download-url';
        return url;
      }
      final thumb = widget.mediaData['thumbnailUrl'];
      if (thumb is String && thumb.isNotEmpty) {
        try {
          log('refreshing from saved thumbnailUrl (image)');
          final fresh = await FirebaseStorage.instance
              .refFromURL(thumb)
              .getDownloadURL();
          if (fresh.isNotEmpty) {
            _lastUrlSource = 'refFromURL(thumbnail)-url';
            return fresh;
          }
        } catch (_) {
          final rehydrated = await _rehydrateFromGcsUrl(thumb);
          if (rehydrated != null && rehydrated.isNotEmpty) {
            _lastUrlSource = 'rehydrated-gcs-thumb-url';
            return rehydrated;
          }
        }
        log('using saved thumbnailUrl (image)');
        _lastUrlSource = 'saved-thumb-url';
        return thumb;
      }
    } else {
      final thumb = widget.mediaData['thumbnailUrl'] as String?;
      if (thumb != null && thumb.isNotEmpty) {
        // Try refresh/rehydrate first
        try {
          final fresh = await FirebaseStorage.instance
              .refFromURL(thumb)
              .getDownloadURL();
          if (fresh.isNotEmpty) {
            _lastUrlSource = 'refFromURL(thumbnail)-url';
            return fresh;
          }
        } catch (_) {
          final rehydrated = await _rehydrateFromGcsUrl(thumb);
          if (rehydrated != null && rehydrated.isNotEmpty) {
            _lastUrlSource = 'rehydrated-gcs-thumb-url';
            return rehydrated;
          }
        }
        log('using saved thumbnailUrl');
        return thumb;
      }
      final url = widget.mediaData['downloadUrl'] as String?;
      if (url != null && url.isNotEmpty) {
        try {
          final fresh = await FirebaseStorage.instance
              .refFromURL(url)
              .getDownloadURL();
          if (fresh.isNotEmpty) {
            _lastUrlSource = 'refFromURL(downloadUrl)-url';
            return fresh;
          }
        } catch (_) {
          final rehydrated = await _rehydrateFromGcsUrl(url);
          if (rehydrated != null && rehydrated.isNotEmpty) {
            _lastUrlSource = 'rehydrated-gcs-download-url';
            return rehydrated;
          }
        }
        log('using saved downloadUrl');
        return url;
      }
    }

    // Last-chance resolve by listing folder and matching fileName
    final mediaType2 = widget.mediaData['mediaType'] as String?;
    final uploadedBy2 = widget.mediaData['uploadedBy'] as String?;
    final fileName2 = widget.mediaData['fileName'] as String?;
    if (mediaType2 == 'image' && uploadedBy2 != null && fileName2 != null) {
      try {
        final baseRef = FirebaseStorage.instance.ref(
          'media/$uploadedBy2/$mediaType2',
        );
        final list = await baseRef.listAll();
        // Prefer exact uniqueFileName match if present
        final unique = widget.mediaData['uniqueFileName'] as String?;
        Reference match = list.items.isNotEmpty ? list.items.first : baseRef;
        if (unique != null && unique.isNotEmpty) {
          final exact = list.items.where((r) => r.name == unique).toList();
          if (exact.isNotEmpty) {
            match = exact.first;
          } else {
            final tail = list.items
                .where(
                  (r) => r.name.toLowerCase().endsWith(fileName2.toLowerCase()),
                )
                .toList();
            if (tail.isNotEmpty) match = tail.first;
          }
        } else {
          final tail = list.items
              .where(
                (r) => r.name.toLowerCase().endsWith(fileName2.toLowerCase()),
              )
              .toList();
          if (tail.isNotEmpty) match = tail.first;
        }
        if (match.fullPath != baseRef.fullPath) {
          log('resolved by listing: ${match.fullPath}');
          _lastUrlSource = 'list-match-url';
          return await match.getDownloadURL();
        }
      } catch (_) {}
    }
    final fallbackDoc = await tryDocUrl(allowRawFallback: true);
    if (fallbackDoc != null) {
      return fallbackDoc;
    }
    return null;
  }

  // Resolve the ORIGINAL image URL for full-screen preview.
  // This prioritizes the real object over any thumbnail.
  Future<String?> _resolveOriginalImageUrl() async {
    // 1) Try fresh from storagePath (best, handles stale tokens)
    final storagePath = widget.mediaData['storagePath'] ?? _guessStoragePath();
    if (storagePath is String && storagePath.isNotEmpty) {
      try {
        final fresh = await FirebaseStorage.instance
            .ref(storagePath)
            .getDownloadURL();
        if (fresh.isNotEmpty) return fresh;
      } catch (_) {}
    }

    // 2) Try saved downloadUrl refreshed via refFromURL
    final url = widget.mediaData['downloadUrl'] as String?;
    if (url != null && url.isNotEmpty) {
      try {
        final fresh = await FirebaseStorage.instance
            .refFromURL(url)
            .getDownloadURL();
        if (fresh.isNotEmpty) return fresh;
      } catch (_) {
        final re = await _rehydrateFromGcsUrl(url);
        if (re != null && re.isNotEmpty) return re;
      }
      return url;
    }

    // 3) As a last resort, use the thumbnail URL if that's all we have
    final thumb = widget.mediaData['thumbnailUrl'] as String?;
    if (thumb != null && thumb.isNotEmpty) {
      try {
        final fresh = await FirebaseStorage.instance
            .refFromURL(thumb)
            .getDownloadURL();
        if (fresh.isNotEmpty) return fresh;
      } catch (_) {
        final re = await _rehydrateFromGcsUrl(thumb);
        if (re != null && re.isNotEmpty) return re;
      }
      return thumb;
    }
    return null;
  }

  Future<Uint8List?> _storageFetchBytes(String url) async {
    try {
      final ref = FirebaseStorage.instance.refFromURL(url);
      final data = await ref.getData(5 * 1024 * 1024);
      if (data != null && data.isNotEmpty) {
        return data;
      }
    } catch (_) {}
    return null;
  }

  // If a stored URL came from the GCS web console (storage.googleapis.com or
  // storage.cloud.google.com), convert it into a proper Firebase download URL
  // by resolving its Storage reference and calling getDownloadURL().
  Future<String?> _rehydrateFromGcsUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (!host.contains('storage.googleapis.com') &&
          !host.contains('storage.cloud.google.com')) {
        return null;
      }

      // Attempt to extract bucket and object for common GCS URL shapes
      // 1) storage.cloud.google.com/<bucket>/<object...>
      // 2) storage.googleapis.com/<bucket>/<object...>
      // 3) storage.googleapis.com/download/storage/v1/b/<bucket>/o/<object>
      // 4) storage.googleapis.com/storage/v1/b/<bucket>/o/<object>
      // We only need bucket + object to create a Storage ref.

      String bucket = '';
      String objectPath = '';

      List<String> segs = List.of(uri.pathSegments);
      if (segs.isEmpty) return null;

      bool jsonApiStyle = false;
      final joined = segs.join('/');
      if (joined.startsWith('download/storage/v1/') ||
          joined.startsWith('storage/v1/')) {
        jsonApiStyle = true;
      }

      if (jsonApiStyle) {
        // download/storage/v1/b/<bucket>/o/<object>
        // Find indices of 'b' and 'o'
        final bIndex = segs.indexOf('b');
        final oIndex = segs.indexOf('o');
        if (bIndex != -1 && (bIndex + 1) < segs.length) {
          bucket = segs[bIndex + 1];
        }
        if (oIndex != -1 && (oIndex + 1) < segs.length) {
          objectPath = segs.sublist(oIndex + 1).join('/');
        }
      } else {
        // cloud console and simple domain style
        bucket = segs.first;
        if (segs.length > 1) {
          objectPath = segs.sublist(1).join('/');
        }
      }

      // Decode possible %2F etc. (apply multiple times for safety)
      objectPath = Uri.decodeComponent(objectPath);
      objectPath = Uri.decodeFull(objectPath);

      if (objectPath.isEmpty) return null;

      // Some console links may include "/o/" in the path – strip it.
      if (objectPath.startsWith('o/')) {
        objectPath = objectPath.substring(2);
      }

      final storage = FirebaseStorage.instanceFor(bucket: bucket);
      final ref = storage.ref(objectPath);
      final fresh = await ref.getDownloadURL();
      return fresh;
    } catch (_) {
      return null;
    }
  }

  String? _urlHintFromDoc() {
    final type = (widget.mediaData['mediaType'] as String?) ?? '';
    if (type == 'image') {
      final thumb = (widget.mediaData['thumbnailUrl'] as String?) ?? '';
      if (thumb.isNotEmpty) return thumb;
    }
    final url = (widget.mediaData['downloadUrl'] as String?) ?? '';
    return url.isNotEmpty ? url : null;
  }

  String? _guessStoragePath() {
    try {
      final uploadedBy = widget.mediaData['uploadedBy'] as String?;
      final mediaType = widget.mediaData['mediaType'] as String?;
      final uniqueFileName = widget.mediaData['uniqueFileName'] as String?;
      if (uploadedBy != null && mediaType != null && uniqueFileName != null) {
        return 'media/$uploadedBy/$mediaType/$uniqueFileName';
      }
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> _tryLoadThumbBytes() async {
    if (kIsWeb) {
      final hintUrl = _urlHintFromDoc();
      if (hintUrl != null && hintUrl.isNotEmpty) {
        final bytes = await _httpFetchBytes(hintUrl);
        if (bytes != null && bytes.isNotEmpty) {
          _lastByteSource = 'web-http-doc';
          return bytes;
        }
      }
      // Fall through to Storage-based strategies for older docs that lack URLs
    }

    try {
      final mediaType = widget.mediaData['mediaType'] as String?;
      final storagePath =
          (widget.mediaData['storagePath'] as String?) ?? _guessStoragePath();
      final uploadedBy = widget.mediaData['uploadedBy'] as String?;
      final uniqueFileName = widget.mediaData['uniqueFileName'] as String?;
      if (mediaType != null && uploadedBy != null && uniqueFileName != null) {
        final thumbPath =
            'media/$uploadedBy/$mediaType/thumbnails/$uniqueFileName.jpg';
        try {
          if (kDebugMode) {
            // ignore: avoid_print
            print('[MediaGridItem:bytes] try thumb $thumbPath');
          }
          final data = await FirebaseStorage.instance
              .ref(thumbPath)
              .getData(2 * 1024 * 1024);
          if (data != null && data.isNotEmpty) {
            if (kDebugMode) {
              // ignore: avoid_print
              print('[MediaGridItem:bytes] thumb OK');
            }
            _lastByteSource = 'thumb-bytes';
            return data;
          }
        } catch (_) {}
      }
      // Fallback: for images, try original object bytes (small images)
      if (mediaType == 'image' && storagePath != null) {
        try {
          if (kDebugMode) {
            // ignore: avoid_print
            print('[MediaGridItem:bytes] try original $storagePath');
          }
          final data = await FirebaseStorage.instance
              .ref(storagePath)
              .getData(5 * 1024 * 1024);
          if (data != null && data.isNotEmpty) {
            if (kDebugMode) {
              // ignore: avoid_print
              print('[MediaGridItem:bytes] original OK');
            }
            _lastByteSource = 'original-bytes';
            return data;
          }
        } catch (_) {}
      }
      // Try listing folder and matching by fileName if storagePath is unknown
      if (mediaType == 'image') {
        final uploadedBy2 = widget.mediaData['uploadedBy'] as String?;
        final fileName2 = widget.mediaData['fileName'] as String?;
        final unique = widget.mediaData['uniqueFileName'] as String?;
        if (uploadedBy2 != null && (fileName2 != null || unique != null)) {
          try {
            final baseRef = FirebaseStorage.instance.ref(
              'media/$uploadedBy2/$mediaType',
            );
            if (kDebugMode) {
              // ignore: avoid_print
              print(
                '[MediaGridItem:bytes] try list match in ${baseRef.fullPath}',
              );
            }
            final list = await baseRef.listAll();
            Reference? target;
            if (unique != null && unique.isNotEmpty) {
              final exact = list.items.where((r) => r.name == unique).toList();
              if (exact.isNotEmpty) target = exact.first;
            }
            if (target == null && fileName2 != null) {
              final tail = list.items
                  .where(
                    (r) =>
                        r.name.toLowerCase().endsWith(fileName2.toLowerCase()),
                  )
                  .toList();
              if (tail.isNotEmpty) target = tail.first;
            }
            if (target != null) {
              final data = await target.getData(5 * 1024 * 1024);
              if (data != null && data.isNotEmpty) {
                if (kDebugMode) {
                  // ignore: avoid_print
                  print(
                    '[MediaGridItem:bytes] list match OK ${target.fullPath}',
                  );
                }
                _lastByteSource = 'listmatch-bytes';
                return data;
              }
            }
          } catch (_) {}
        }
      }
      // Try using the downloadUrl via Storage SDK (refFromURL) for images
      if (mediaType == 'image') {
        final url = widget.mediaData['downloadUrl'] as String?;
        if (url != null && url.isNotEmpty) {
          try {
            if (kDebugMode) {
              // ignore: avoid_print
              print('[MediaGridItem:bytes] try refFromURL');
            }
            final data = await FirebaseStorage.instance
                .refFromURL(url)
                .getData(5 * 1024 * 1024);
            if (data != null && data.isNotEmpty) {
              if (kDebugMode) {
                // ignore: avoid_print
                print('[MediaGridItem:bytes] refFromURL OK');
              }
              _lastByteSource = 'refFromURL-bytes';
              return data;
            }
          } catch (_) {}
        }
      }
      // Final fallback for images: fetch bytes over HTTP from downloadUrl
      if (mediaType == 'image') {
        final url = widget.mediaData['downloadUrl'] as String?;
        if (url != null && url.isNotEmpty) {
          try {
            if (kDebugMode) {
              // ignore: avoid_print
              print('[MediaGridItem:bytes] try HTTP GET');
            }
            final resp = await http.get(Uri.parse(url));
            if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
              if (kDebugMode) {
                // ignore: avoid_print
                print('[MediaGridItem:bytes] HTTP OK');
              }
              _lastByteSource = 'http-bytes';
              return resp.bodyBytes;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return null;
  }

  IconData _getFileIcon(String mediaType) {
    switch (mediaType) {
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.video_library;
      case 'audio':
        return Icons.audio_file;
      case 'document':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getTypeColor(String mediaType) {
    switch (mediaType) {
      case 'image':
        return Colors.green;
      case 'video':
        return Colors.red;
      case 'audio':
        return Colors.purple;
      case 'document':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _fallbackTile(String mediaType) {
    return Container(
      color: _getTypeColor(mediaType).withOpacity(0.1),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _getFileIcon(mediaType),
            size: 48,
            color: _getTypeColor(mediaType),
          ),
          const SizedBox(height: 8),
          Text(
            mediaType.toUpperCase(),
            style: TextStyle(
              color: _getTypeColor(mediaType),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _showMediaDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Try bytes-first for a guaranteed preview (thumbnail or original). If unavailable, fall back to resolved URL.
                FutureBuilder<Uint8List?>(
                  future: _thumbBytesFuture,
                  builder: (context, bSnap) {
                    if (bSnap.connectionState == ConnectionState.waiting) {
                      return Container(
                        color: Colors.grey[300],
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    }
                    final bytes = bSnap.data;
                    if (bytes != null && bytes.isNotEmpty) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(bytes, fit: BoxFit.cover),
                      );
                    }
                    return FutureBuilder<String?>(
                      future: _resolvedUrlFuture,
                      builder: (context, snap) {
                        final url = snap.data;
                        if (snap.connectionState == ConnectionState.waiting) {
                          return Container(
                            color: Colors.grey[300],
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        if (url != null && url.isNotEmpty) {
                          final type =
                              (widget.mediaData['mediaType'] as String?) ?? '';
                          if (type == 'image') {
                            final download =
                                (widget.mediaData['downloadUrl'] as String?) ??
                                '';
                            final thumb =
                                (widget.mediaData['thumbnailUrl'] as String?) ??
                                '';
                            final alt = url == download ? thumb : download;
                            return _imageFromUrl(url, alt: alt);
                          }
                          return CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            placeholder: (context, _) => Container(
                              color: Colors.grey[300],
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            errorWidget: (context, _, __) => Container(
                              color: _getTypeColor(
                                widget.mediaData['mediaType'],
                              ).withOpacity(0.1),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _getFileIcon(widget.mediaData['mediaType']),
                                    size: 48,
                                    color: _getTypeColor(
                                      widget.mediaData['mediaType'],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.mediaData['mediaType']
                                        .toString()
                                        .toUpperCase(),
                                    style: TextStyle(
                                      color: _getTypeColor(
                                        widget.mediaData['mediaType'],
                                      ),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return Container(
                          color: _getTypeColor(
                            widget.mediaData['mediaType'],
                          ).withOpacity(0.1),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _getFileIcon(widget.mediaData['mediaType']),
                                size: 48,
                                color: _getTypeColor(
                                  widget.mediaData['mediaType'],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.mediaData['mediaType']
                                    .toString()
                                    .toUpperCase(),
                                style: TextStyle(
                                  color: _getTypeColor(
                                    widget.mediaData['mediaType'],
                                  ),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),

                const SizedBox(height: 20),

                // File details
                Text(
                  'File Details',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                _buildDetailRow(
                  'Name',
                  widget.mediaData['fileName'] ?? 'Unknown',
                ),
                _buildDetailRow(
                  'Type',
                  widget.mediaData['mediaType'] ?? 'Unknown',
                ),
                _buildDetailRow(
                  'Size',
                  MediaStorageService.formatFileSize(
                    widget.mediaData['fileSize'] ?? 0,
                  ),
                ),
                _buildDetailRow(
                  'Format',
                  widget.mediaData['contentType'] ?? 'Unknown',
                ),

                const SizedBox(height: 24),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final resolved = await _resolvedUrlFuture;
                          if (resolved == null || resolved.isEmpty) return;
                          final url = Uri.parse(resolved);
                          if (await canLaunchUrl(url)) {
                            await launchUrl(
                              url,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('Download'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[600],
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showDeleteConfirmation(context);
                        },
                        icon: const Icon(Icons.delete),
                        label: const Text('Delete'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text(
          'Are you sure you want to delete "${widget.mediaData['fileName']}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (_) {
            final storagePath =
                (widget.mediaData['storagePath'] ?? '') as String;
            final unique = (widget.mediaData['uniqueFileName'] ?? '') as String;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Diagnostics',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'byte source: ${_lastByteSource.isEmpty ? 'n/a' : _lastByteSource}',
                  ),
                  Text(
                    'url source: ${_lastUrlSource.isEmpty ? 'n/a' : _lastUrlSource}',
                  ),
                  if (storagePath.isNotEmpty) Text('storagePath: $storagePath'),
                  if (unique.isNotEmpty) Text('uniqueFileName: $unique'),
                ],
              ),
            );
          },
        );
      },
      onTap: () {
        final type = widget.mediaData['mediaType'] as String?;
        if (type == 'video') {
          final url = widget.mediaData['downloadUrl'] as String?;
          if (url != null && url.isNotEmpty) {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              builder: (_) => VideoPlayerSheet(
                url: url,
                title: widget.mediaData['fileName'] as String?,
              ),
            );
            return;
          }
        }
        if (type == 'image') {
          _showFullImage(context);
          return;
        }
        if (type == 'document') {
          final contentType =
              (widget.mediaData['contentType'] as String?) ?? '';
          final isPdf =
              contentType.contains('pdf') ||
              (widget.mediaData['fileName'] as String?)?.toLowerCase().endsWith(
                    '.pdf',
                  ) ==
                  true;
          if (isPdf) {
            _openPdf(context);
            return;
          }
        }
        _showMediaDetails(context);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: FutureBuilder<Uint8List?>(
                  future: _thumbBytesFuture,
                  builder: (context, bSnap) {
                    if (bSnap.connectionState == ConnectionState.waiting) {
                      return Container(
                        color: Colors.grey[300],
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    }
                    final bytes = bSnap.data;
                    if (bytes != null && bytes.isNotEmpty) {
                      return Image.memory(bytes, fit: BoxFit.cover);
                    }
                    return FutureBuilder<String?>(
                      future: _resolvedUrlFuture,
                      builder: (context, snap) {
                        final url = snap.data;
                        if (snap.connectionState == ConnectionState.waiting) {
                          return Container(
                            color: Colors.grey[300],
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        if (url != null && url.isNotEmpty) {
                          final type =
                              (widget.mediaData['mediaType'] as String?) ?? '';
                          if (type == 'image') {
                            final download =
                                (widget.mediaData['downloadUrl'] as String?) ??
                                '';
                            final thumb =
                                (widget.mediaData['thumbnailUrl'] as String?) ??
                                '';
                            final alt = url == download ? thumb : download;
                            return _imageFromUrl(url, alt: alt);
                          }
                          return CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            placeholder: (context, _) => Container(
                              color: Colors.grey[300],
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            errorWidget: (context, _, __) => Container(
                              color: _getTypeColor(
                                widget.mediaData['mediaType'],
                              ).withOpacity(0.1),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _getFileIcon(widget.mediaData['mediaType']),
                                    size: 48,
                                    color: _getTypeColor(
                                      widget.mediaData['mediaType'],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.mediaData['mediaType']
                                        .toString()
                                        .toUpperCase(),
                                    style: TextStyle(
                                      color: _getTypeColor(
                                        widget.mediaData['mediaType'],
                                      ),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return Container(
                          color: _getTypeColor(
                            widget.mediaData['mediaType'],
                          ).withOpacity(0.1),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _getFileIcon(widget.mediaData['mediaType']),
                                size: 48,
                                color: _getTypeColor(
                                  widget.mediaData['mediaType'],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.mediaData['mediaType']
                                    .toString()
                                    .toUpperCase(),
                                style: TextStyle(
                                  color: _getTypeColor(
                                    widget.mediaData['mediaType'],
                                  ),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.mediaData['fileName'] ?? 'Unknown',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    MediaStorageService.formatFileSize(
                      widget.mediaData['fileSize'] ?? 0,
                    ),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPdf(BuildContext context) async {
    final resolved = await _resolvedUrlFuture;
    if (!mounted) return;
    if (resolved == null || resolved.isEmpty) {
      _showMediaDetails(context);
      return;
    }
    if (kIsWeb) {
      // On web, open in new tab for best PDF support
      final uri = Uri.parse(resolved);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, webOnlyWindowName: '_blank');
      }
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: PdfViewerSheet(
          url: resolved,
          title: widget.mediaData['fileName'] as String?,
        ),
      ),
    );
  }

  Future<void> _showFullImage(BuildContext context) async {
    // Always prefer the ORIGINAL file in full screen
    final originalUrl = await _resolveOriginalImageUrl();
    // As a backup, get any bytes we can (thumb or original small)
    final bytes = await _tryLoadThumbBytes();
    if (!mounted) return;

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withOpacity(0.95),
      pageBuilder: (context, anim1, anim2) {
        Widget content;
        if (originalUrl != null && originalUrl.isNotEmpty) {
          final download = (widget.mediaData['downloadUrl'] as String?) ?? '';
          final thumb = (widget.mediaData['thumbnailUrl'] as String?) ?? '';
          final alt = originalUrl == download ? thumb : download;
          content = _imageFromUrl(originalUrl, alt: alt, fit: BoxFit.contain);
        } else if (bytes != null && bytes.isNotEmpty) {
          content = Image.memory(bytes, fit: BoxFit.contain);
        } else {
          content = _fallbackTile('image');
        }

        return Material(
          color: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 6,
                  child: Center(child: content),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  tooltip: 'Close',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
