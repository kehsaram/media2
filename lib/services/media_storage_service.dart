import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path/path.dart' as path;
import 'package:mime/mime.dart' as mime;
import 'package:image/image.dart' as img;
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

class MediaStorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Upload media file to Firebase Storage
  Future<Map<String, dynamic>> uploadMedia({
    required File file,
    required String mediaType, // 'image', 'video', 'document', 'audio'
    String? customName,
    Function(double)? onProgress,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      final fileName = customName ?? path.basename(file.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final uniqueFileName = '${timestamp}_$fileName';

      // Create storage reference
      final storageRef = _storage.ref().child(
        'media/${user.uid}/$mediaType/$uniqueFileName',
      );

      // Guess content type
      String contentType =
          mime.lookupMimeType(file.path) ?? 'application/octet-stream';

      UploadTask uploadTask;
      // For images, normalize orientation and optionally resize/compress before upload
      if (mediaType == 'image') {
        try {
          final original = await file.readAsBytes();
          final processed = _processImageForUpload(
            original,
            fileName: path.basename(file.path),
            originalContentType: contentType,
          );
          contentType = processed.contentType;
          uploadTask = storageRef.putData(
            processed.bytes,
            SettableMetadata(contentType: contentType),
          );
        } catch (_) {
          // Fall back to raw file upload if processing fails
          uploadTask = storageRef.putFile(
            file,
            SettableMetadata(contentType: contentType),
          );
        }
      } else {
        // Non-image: upload as-is
        uploadTask = storageRef.putFile(
          file,
          SettableMetadata(contentType: contentType),
        );
      }

      // Monitor upload progress
      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          onProgress(progress);
        });
      }

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Generate and upload thumbnail when possible
      String? thumbnailUrl;
      try {
        final thumbBytes = await _generateThumbnailForFile(
          file: file,
          mediaType: mediaType,
        );
        if (thumbBytes != null) {
          thumbnailUrl = await _uploadThumbnail(
            bytes: thumbBytes,
            userId: user.uid,
            mediaType: mediaType,
            uniqueFileName: uniqueFileName,
          );
        }
      } catch (_) {
        // Ignore thumbnail errors
      }

      // Get file metadata
      final metadata = await snapshot.ref.getMetadata();

      // Create media document in Firestore
      final mediaDoc = {
        'fileName': fileName,
        'uniqueFileName': uniqueFileName,
        'downloadUrl': downloadUrl,
        'mediaType': mediaType,
        'fileSize': metadata.size,
        'contentType': metadata.contentType,
        'uploadedBy': user.uid,
        'uploadedByEmail': user.email,
        'uploadedAt': FieldValue.serverTimestamp(),
        'storagePath': storageRef.fullPath,
        if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      };

      final docRef = await _firestore.collection('media').add(mediaDoc);

      return {
        'success': true,
        'documentId': docRef.id,
        'downloadUrl': downloadUrl,
        'fileName': fileName,
        'mediaType': mediaType,
        'fileSize': metadata.size,
      };
    } catch (e) {
      throw 'Failed to upload media: ${e.toString()}';
    }
  }

  // Upload media from bytes (for Web or when you already have the bytes)
  Future<Map<String, dynamic>> uploadMediaBytes({
    required Uint8List bytes,
    required String fileName,
    required String mediaType, // 'image', 'video', 'document', 'audio'
    String? customName,
    Function(double)? onProgress,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      final fileName0 = customName ?? fileName;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final uniqueFileName = '${timestamp}_$fileName0';

      final storageRef = _storage.ref().child(
        'media/${user.uid}/$mediaType/$uniqueFileName',
      );

      String contentType =
          mime.lookupMimeType(fileName0) ?? 'application/octet-stream';

      Uint8List toUpload = bytes;
      if (mediaType == 'image') {
        try {
          final processed = _processImageForUpload(
            bytes,
            fileName: fileName0,
            originalContentType: contentType,
          );
          toUpload = processed.bytes;
          contentType = processed.contentType;
        } catch (_) {}
      }

      final uploadTask = storageRef.putData(
        toUpload,
        SettableMetadata(contentType: contentType),
      );

      if (onProgress != null) {
        final total = bytes.lengthInBytes;
        uploadTask.snapshotEvents.listen(
          (TaskSnapshot snapshot) {
            double progress = 0.0;
            if (total > 0) {
              progress = snapshot.bytesTransferred / total;
              if (progress.isNaN || !progress.isFinite) progress = 0.0;
            }
            onProgress(progress.clamp(0.0, 1.0));
          },
          onError: (_) {
            // Ensure UI stops indeterminate state on error
            onProgress(0.0);
          },
        );
      }

      final snapshot = await uploadTask;
      // Ensure progress shows complete
      if (onProgress != null) onProgress(1.0);
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Generate and upload thumbnail when possible (bytes path)
      String? thumbnailUrl;
      try {
        final thumbBytes = await _generateThumbnailFromBytes(
          bytes: bytes,
          fileName: fileName0,
          mediaType: mediaType,
        );
        if (thumbBytes != null) {
          thumbnailUrl = await _uploadThumbnail(
            bytes: thumbBytes,
            userId: user.uid,
            mediaType: mediaType,
            uniqueFileName: uniqueFileName,
          );
        }
      } catch (_) {}

      final metadata = await snapshot.ref.getMetadata();

      final mediaDoc = {
        'fileName': fileName0,
        'uniqueFileName': uniqueFileName,
        'downloadUrl': downloadUrl,
        'mediaType': mediaType,
        'fileSize': metadata.size,
        'contentType': metadata.contentType,
        'uploadedBy': user.uid,
        'uploadedByEmail': user.email,
        'uploadedAt': FieldValue.serverTimestamp(),
        'storagePath': storageRef.fullPath,
        if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      };

      final docRef = await _firestore.collection('media').add(mediaDoc);

      return {
        'success': true,
        'documentId': docRef.id,
        'downloadUrl': downloadUrl,
        'fileName': fileName0,
        'mediaType': mediaType,
        'fileSize': metadata.size,
      };
    } catch (e) {
      throw 'Failed to upload media: ${e.toString()}';
    }
  }

  // Process image bytes for upload: normalize EXIF orientation and bound size
  _ImageProcessResult _processImageForUpload(
    Uint8List bytes, {
    required String fileName,
    required String originalContentType,
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return _ImageProcessResult(
        bytes: bytes,
        contentType: originalContentType,
      );
    }

    // Normalize EXIF orientation
    final baked = img.bakeOrientation(decoded);

    // Resize if larger than a safe bound (keeps aspect)
    const int maxDim = 4096;
    img.Image processed = baked;
    if (baked.width > maxDim || baked.height > maxDim) {
      processed = img.copyResize(
        baked,
        width: baked.width > baked.height ? maxDim : null,
        height: baked.height >= baked.width ? maxDim : null,
        maintainAspect: true,
      );
    }

    // Preserve transparency with PNG, otherwise prefer high-quality JPEG
    final lower = fileName.toLowerCase();
    final prefersPng =
        lower.endsWith('.png') || lower.endsWith('.webp') || processed.hasAlpha;
    if (prefersPng) {
      final out = img.encodePng(processed, level: 6);
      return _ImageProcessResult(
        bytes: Uint8List.fromList(out),
        contentType: 'image/png',
      );
    } else {
      final out = img.encodeJpg(processed, quality: 85);
      return _ImageProcessResult(
        bytes: Uint8List.fromList(out),
        contentType: 'image/jpeg',
      );
    }
  }

  // --- Thumbnail helpers ---
  Future<Uint8List?> _generateThumbnailForFile({
    required File file,
    required String mediaType,
  }) async {
    try {
      switch (mediaType) {
        case 'image':
          final bytes = await file.readAsBytes();
          return _generateImageThumbnail(bytes);
        case 'video':
          // Not supported on web via this path; this File path is mobile/desktop
          final thumb = await vt.VideoThumbnail.thumbnailData(
            video: file.path,
            imageFormat: vt.ImageFormat.JPEG,
            maxHeight: 320,
            quality: 80,
          );
          return thumb;
        case 'document':
          return _generatePlaceholderThumbnail('DOC');
        case 'audio':
          return _generatePlaceholderThumbnail('AUDIO');
      }
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> _generateThumbnailFromBytes({
    required Uint8List bytes,
    required String fileName,
    required String mediaType,
  }) async {
    try {
      switch (mediaType) {
        case 'image':
          return _generateImageThumbnail(bytes);
        case 'video':
          // video_thumbnail doesn't support web/bytes; fallback placeholder
          return _generatePlaceholderThumbnail('VIDEO');
        case 'document':
          final ext = path
              .extension(fileName)
              .replaceAll('.', '')
              .toUpperCase();
          return _generatePlaceholderThumbnail(ext.isEmpty ? 'DOC' : ext);
        case 'audio':
          return _generatePlaceholderThumbnail('AUDIO');
      }
    } catch (_) {}
    return null;
  }

  Uint8List? _generateImageThumbnail(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final resized = img.copyResize(
        decoded,
        width: 480,
        height: 480,
        maintainAspect: true,
      );
      final jpg = img.encodeJpg(resized, quality: 80);
      return Uint8List.fromList(jpg);
    } catch (_) {
      return null;
    }
  }

  Uint8List? _generatePlaceholderThumbnail(String label) {
    try {
      final w = 480, h = 300;
      final image = img.Image(width: w, height: h);
      // background color by hash of label
      final hash = label.hashCode;
      final r = 100 + (hash & 0x5F);
      final g = 100 + ((hash >> 3) & 0x5F);
      final b = 100 + ((hash >> 6) & 0x5F);
      img.fill(image, color: img.ColorRgb8(r, g, b));
      // Simple white circle mark in center as placeholder symbol
      final radius = (w < h ? w : h) ~/ 6;
      img.fillCircle(
        image,
        x: w ~/ 2,
        y: h ~/ 2,
        radius: radius,
        color: img.ColorRgb8(255, 255, 255),
        antialias: true,
      );
      final jpg = img.encodeJpg(image, quality: 80);
      return Uint8List.fromList(jpg);
    } catch (_) {
      return null;
    }
  }

  Future<String> _uploadThumbnail({
    required Uint8List bytes,
    required String userId,
    required String mediaType,
    required String uniqueFileName,
  }) async {
    final thumbRef = _storage.ref().child(
      'media/$userId/$mediaType/thumbnails/$uniqueFileName.jpg',
    );
    final task = await thumbRef.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return task.ref.getDownloadURL();
  }

  // Get user's media files
  Stream<QuerySnapshot> getUserMedia({String? mediaType}) {
    final user = _auth.currentUser;
    if (user == null) {
      throw 'User not authenticated';
    }

    Query query = _firestore
        .collection('media')
        .where('uploadedBy', isEqualTo: user.uid)
        .orderBy('uploadedAt', descending: true);

    if (mediaType != null) {
      query = query.where('mediaType', isEqualTo: mediaType);
    }

    return query.snapshots();
  }

  // Get all media (any uploader) for authenticated users
  Stream<QuerySnapshot> getAllMedia({String? mediaType}) {
    Query query = _firestore
        .collection('media')
        .orderBy('uploadedAt', descending: true);

    if (mediaType != null) {
      query = query.where('mediaType', isEqualTo: mediaType);
    }

    return query.snapshots();
  }

  // Delete media file
  Future<void> deleteMedia(String documentId, String storagePath) async {
    try {
      // Delete from Storage
      await _storage.ref(storagePath).delete();

      // Delete from Firestore
      await _firestore.collection('media').doc(documentId).delete();
    } catch (e) {
      throw 'Failed to delete media: ${e.toString()}';
    }
  }

  // Get media by type for current user
  Future<List<Map<String, dynamic>>> getMediaByType(String mediaType) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      final querySnapshot = await _firestore
          .collection('media')
          .where('uploadedBy', isEqualTo: user.uid)
          .where('mediaType', isEqualTo: mediaType)
          .orderBy('uploadedAt', descending: true)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw 'Failed to fetch media: ${e.toString()}';
    }
  }

  // Update media metadata
  Future<void> updateMediaMetadata(
    String documentId,
    Map<String, dynamic> updates,
  ) async {
    try {
      await _firestore.collection('media').doc(documentId).update(updates);
    } catch (e) {
      throw 'Failed to update media: ${e.toString()}';
    }
  }

  // Get storage usage for user
  Future<Map<String, dynamic>> getStorageUsage() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      final querySnapshot = await _firestore
          .collection('media')
          .where('uploadedBy', isEqualTo: user.uid)
          .get();

      int totalFiles = querySnapshot.docs.length;
      int totalSize = 0;
      Map<String, int> filesByType = {};

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        totalSize += (data['fileSize'] ?? 0) as int;

        final mediaType = data['mediaType'] ?? 'unknown';
        filesByType[mediaType] = (filesByType[mediaType] ?? 0) + 1;
      }

      return {
        'totalFiles': totalFiles,
        'totalSize': totalSize,
        'filesByType': filesByType,
      };
    } catch (e) {
      throw 'Failed to get storage usage: ${e.toString()}';
    }
  }

  // Backfill thumbnails for current user (images only for now)
  // Returns counts: processed, created, skipped, failed
  Future<Map<String, int>> backfillThumbnailsForCurrentUser({
    String? mediaTypeFilter,
    int maxItems = 100,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw 'User not authenticated';
    }

    int processed = 0;
    int created = 0;
    int skipped = 0;
    int failed = 0;

    try {
      Query query = _firestore
          .collection('media')
          .where('uploadedBy', isEqualTo: user.uid)
          .orderBy('uploadedAt', descending: true)
          .limit(maxItems);

      if (mediaTypeFilter != null) {
        query = query.where('mediaType', isEqualTo: mediaTypeFilter);
      }

      final snap = await query.get();
      for (final doc in snap.docs) {
        processed++;
        final data = doc.data() as Map<String, dynamic>?;
        final mediaType = (data?['mediaType'] ?? '') as String;
        final hasThumb = (data?['thumbnailUrl'] ?? '').toString().isNotEmpty;
        if (hasThumb) {
          skipped++;
          continue;
        }
        if (mediaType != 'image') {
          skipped++;
          continue;
        }

        try {
          final storagePath = (data?['storagePath'] ?? '') as String;
          if (storagePath.isEmpty) {
            // Attempt derive from fields
            final uploadedBy = (data?['uploadedBy'] ?? '') as String;
            final uniqueFileName = (data?['uniqueFileName'] ?? '') as String;
            if (uploadedBy.isEmpty || uniqueFileName.isEmpty) {
              failed++;
              continue;
            }
            final guessed = 'media/$uploadedBy/$mediaType/$uniqueFileName';
            final ref = _storage.ref(guessed);
            final bytes = await ref.getData(6 * 1024 * 1024);
            if (bytes == null || bytes.isEmpty) {
              failed++;
              continue;
            }
            final thumb = _generateImageThumbnail(bytes);
            if (thumb == null) {
              failed++;
              continue;
            }
            final thumbUrl = await _uploadThumbnail(
              bytes: thumb,
              userId: uploadedBy,
              mediaType: mediaType,
              uniqueFileName: uniqueFileName,
            );
            await doc.reference.update({'thumbnailUrl': thumbUrl});
            created++;
          } else {
            final ref = _storage.ref(storagePath);
            final bytes = await ref.getData(6 * 1024 * 1024);
            if (bytes == null || bytes.isEmpty) {
              failed++;
              continue;
            }
            final thumb = _generateImageThumbnail(bytes);
            if (thumb == null) {
              failed++;
              continue;
            }
            final uploadedBy = (data?['uploadedBy'] ?? '') as String;
            final uniqueFileName = (data?['uniqueFileName'] ?? '') as String;
            final thumbUrl = await _uploadThumbnail(
              bytes: thumb,
              userId: uploadedBy,
              mediaType: mediaType,
              uniqueFileName: uniqueFileName,
            );
            await doc.reference.update({'thumbnailUrl': thumbUrl});
            created++;
          }
        } catch (_) {
          failed++;
        }
      }
    } catch (_) {
      // best-effort utility
    }

    return {
      'processed': processed,
      'created': created,
      'skipped': skipped,
      'failed': failed,
    };
  }

  // Backfill storagePath for current user where missing.
  // Returns counts: processed, updated, skipped, failed
  Future<Map<String, int>> backfillStoragePathForCurrentUser({
    int maxItems = 200,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw 'User not authenticated';
    }
    int processed = 0, updated = 0, skipped = 0, failed = 0;
    try {
      final snap = await _firestore
          .collection('media')
          .where('uploadedBy', isEqualTo: user.uid)
          .orderBy('uploadedAt', descending: true)
          .limit(maxItems)
          .get();
      for (final doc in snap.docs) {
        processed++;
        final data = doc.data() as Map<String, dynamic>?;
        final current = (data?['storagePath'] ?? '') as String;
        if (current.isNotEmpty) {
          skipped++;
          continue;
        }
        final mediaType = (data?['mediaType'] ?? '') as String;
        final uploadedBy = (data?['uploadedBy'] ?? '') as String;
        final uniqueFileName = (data?['uniqueFileName'] ?? '') as String;
        String? derived;
        try {
          final durl = (data?['downloadUrl'] ?? '') as String;
          if (durl.isNotEmpty) {
            derived = FirebaseStorage.instance.refFromURL(durl).fullPath;
          }
        } catch (_) {}
        if (derived == null || derived.isEmpty) {
          try {
            final turl = (data?['thumbnailUrl'] ?? '') as String;
            if (turl.isNotEmpty) {
              final thumbPath = FirebaseStorage.instance
                  .refFromURL(turl)
                  .fullPath;
              // derive parent folder from thumb
              // thumb is media/{uid}/{type}/thumbnails/{unique}.jpg
              final folder = thumbPath.split('/thumbnails/').first;
              if (folder.isNotEmpty && uniqueFileName.isNotEmpty) {
                derived = '$folder/$uniqueFileName';
              }
            }
          } catch (_) {}
        }
        if ((derived == null || derived.isEmpty) &&
            uploadedBy.isNotEmpty &&
            mediaType.isNotEmpty &&
            uniqueFileName.isNotEmpty) {
          derived = 'media/$uploadedBy/$mediaType/$uniqueFileName';
        }
        if (derived == null || derived.isEmpty) {
          failed++;
          continue;
        }
        try {
          await doc.reference.update({'storagePath': derived});
          updated++;
        } catch (_) {
          failed++;
        }
      }
    } catch (_) {}

    return {
      'processed': processed,
      'updated': updated,
      'skipped': skipped,
      'failed': failed,
    };
  }

  // Format file size
  static String formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();

    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }

    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  // Get supported media types
  static Map<String, List<String>> getSupportedMediaTypes() {
    return {
      'image': ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
      'video': ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'],
      'audio': ['mp3', 'wav', 'aac', 'ogg', 'flac', 'm4a'],
      'document': [
        'pdf',
        'doc',
        'docx',
        'txt',
        'rtf',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
      ],
    };
  }

  // Determine media type from file extension
  static String getMediaTypeFromExtension(String fileName) {
    final extension = path
        .extension(fileName)
        .toLowerCase()
        .replaceAll('.', '');
    final supportedTypes = getSupportedMediaTypes();

    for (var entry in supportedTypes.entries) {
      if (entry.value.contains(extension)) {
        return entry.key;
      }
    }

    return 'document'; // Default fallback
  }
}

class _ImageProcessResult {
  final Uint8List bytes;
  final String contentType;
  _ImageProcessResult({required this.bytes, required this.contentType});
}
