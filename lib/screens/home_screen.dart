import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/foundation.dart' as foundation;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'dart:typed_data';

import '../services/auth_service.dart';
import '../services/media_storage_service.dart';
import '../widgets/media_grid_item.dart';
import '../widgets/upload_progress_dialog.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final MediaStorageService _mediaService = MediaStorageService();
  final ImagePicker _imagePicker = ImagePicker();

  late TabController _tabController;
  String _currentFilter = 'all';
  bool _hasOngoingUploads = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    // Check for ongoing uploads before signing out
    if (_hasOngoingUploads) {
      final shouldProceed = await _showUncommittedChangesDialog(
        'An upload is currently in progress. Are you sure you want to sign out? This will cancel the upload.',
      );
      
      if (!shouldProceed) {
        return;
      }
    }

    try {
      await _authService.signOut();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error signing out: $e')));
      }
    }
  }

  void _showUploadOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Upload Media',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildUploadOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  color: Colors.blue,
                  onTap: () => _pickImage(ImageSource.camera),
                ),
                _buildUploadOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  color: Colors.green,
                  onTap: () => _pickImage(ImageSource.gallery),
                ),
                _buildUploadOption(
                  icon: Icons.videocam,
                  label: 'Video',
                  color: Colors.red,
                  onTap: () => _pickVideo(),
                ),
                _buildUploadOption(
                  icon: Icons.insert_drive_file,
                  label: 'Files',
                  color: Colors.orange,
                  onTap: () => _pickFile(),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Icon(icon, size: 30, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image != null) {
        if (kIsWeb) {
          final bytes = await image.readAsBytes();
          final name = image.name.isNotEmpty
              ? image.name
              : image.path.split('/').last;
          await _uploadBytes(bytes, name, 'image');
        } else {
          await _uploadFile(File(image.path), 'image');
        }
      }
    } catch (e) {
      _showErrorSnackBar('Error picking image: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
      );
      if (video != null) {
        if (kIsWeb) {
          final bytes = await video.readAsBytes();
          final name = video.name.isNotEmpty
              ? video.name
              : video.path.split('/').last;
          await _uploadBytes(bytes, name, 'video');
        } else {
          await _uploadFile(File(video.path), 'video');
        }
      }
    } catch (e) {
      _showErrorSnackBar('Error picking video: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      // Allow common document and media types; request bytes for cloud providers
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const [
          // documents
          'pdf', 'doc', 'docx', 'txt', 'rtf', 'xls', 'xlsx', 'ppt', 'pptx',
          // images
          'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp',
          // audio
          'mp3', 'wav', 'aac', 'ogg', 'flac', 'm4a',
          // video
          'mp4', 'mov', 'avi', 'mkv', 'webm', '3gp',
        ],
      );

      if (result != null) {
        final picked = result.files.single;
        final name = picked.name;
        // Prefer bytes if available (works on Web and cloud sources on mobile)
        if (picked.bytes != null && picked.bytes!.isNotEmpty) {
          final mediaType = MediaStorageService.getMediaTypeFromExtension(name);
          await _uploadBytes(picked.bytes!, name, mediaType);
        } else if (picked.path != null) {
          final file = File(picked.path!);
          final mediaType = MediaStorageService.getMediaTypeFromExtension(
            file.path,
          );
          await _uploadFile(file, mediaType);
        } else {
          _showErrorSnackBar(
            'Could not read the selected file. Please try another source.',
          );
        }
      }
    } catch (e) {
      _showErrorSnackBar('Error picking file: $e');
    }
  }

  Future<void> _uploadFile(File file, String mediaType) async {
    final progress = ValueNotifier<double>(0.0);

    _setUploadInProgress(true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UploadProgressDialog(
        fileName: file.path.split('/').last,
        progress: progress,
      ),
    );

    try {
      await _mediaService.uploadMedia(
        file: file,
        mediaType: mediaType,
        onProgress: (p) => progress.value = p,
      );

      if (mounted) {
        _setUploadInProgress(false);
        Navigator.pop(context); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _setUploadInProgress(false);
        Navigator.pop(context); // Close progress dialog
        _showErrorSnackBar('Upload failed: $e');
      }
    }
  }

  Future<void> _uploadBytes(
    Uint8List bytes,
    String fileName,
    String mediaType,
  ) async {
    final progress = ValueNotifier<double>(0.0);

    _setUploadInProgress(true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          UploadProgressDialog(fileName: fileName, progress: progress),
    );

    try {
      await _mediaService.uploadMediaBytes(
        bytes: bytes,
        fileName: fileName,
        mediaType: mediaType,
        onProgress: (p) => progress.value = p,
      );

      if (mounted) {
        _setUploadInProgress(false);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _setUploadInProgress(false);
        Navigator.pop(context);
        _showErrorSnackBar('Upload failed: $e');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _setUploadInProgress(bool inProgress) {
    if (mounted) {
      setState(() {
        _hasOngoingUploads = inProgress;
      });
    }
  }

  Future<bool> _showUncommittedChangesDialog(String actionMessage) async {
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uncommitted changes detected'),
        content: Text(actionMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Proceed'),
          ),
        ],
      ),
    );

    return shouldProceed ?? false;
  }

  Future<bool> _onWillPop() async {
    if (!_hasOngoingUploads) {
      return true;
    }

    return await _showUncommittedChangesDialog(
      'An upload is currently in progress. Are you sure you want to leave? This will cancel the upload.',
    );
  }

  Stream<QuerySnapshot> _getFilteredMedia() {
    if (_currentFilter == 'all') {
      return _mediaService.getAllMedia();
    } else {
      return _mediaService.getAllMedia(mediaType: _currentFilter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Media Storage'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                user?.displayName?.substring(0, 1).toUpperCase() ?? 'U',
                style: TextStyle(
                  color: Colors.blue[600],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            onSelected: (value) {
              if (value == 'logout') {
                _signOut();
              } else if (value == 'backfill') {
                _runBackfill();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    const Icon(Icons.person),
                    const SizedBox(width: 8),
                    Text(user?.displayName ?? 'User'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'email',
                child: Row(
                  children: [
                    const Icon(Icons.email),
                    const SizedBox(width: 8),
                    Text(user?.email ?? ''),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('Sign Out'),
                  ],
                ),
              ),
              if (foundation.kDebugMode)
                const PopupMenuItem(
                  value: 'backfill',
                  child: Row(
                    children: [
                      Icon(Icons.build_circle_outlined),
                      SizedBox(width: 8),
                      Text('Backfill thumbnails'),
                    ],
                  ),
                ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          onTap: (index) {
            setState(() {
              _currentFilter = [
                'all',
                'image',
                'video',
                'audio',
                'document',
              ][index];
            });
          },
          tabs: const [
            Tab(text: 'All', icon: Icon(Icons.grid_view)),
            Tab(text: 'Images', icon: Icon(Icons.image)),
            Tab(text: 'Videos', icon: Icon(Icons.video_library)),
            Tab(text: 'Audio', icon: Icon(Icons.audio_file)),
            Tab(text: 'Documents', icon: Icon(Icons.description)),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getFilteredMedia(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final err = snapshot.error;
            // Friendly message while Firestore builds a required composite index
            if (err is FirebaseException &&
                err.code == 'failed-precondition' &&
                (err.message ?? '').toLowerCase().contains('index')) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.insights_outlined,
                        size: 64,
                        color: Colors.orange[600],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Preparing this view…',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Firestore is building an index for this filter. This typically takes 1–2 minutes. You can stay on this screen and retry shortly.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => setState(() {}),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry now'),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_upload, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No media files yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the + button to upload your first file',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1,
            ),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              data['id'] = docs[index].id;
              return MediaGridItem(
                mediaData: data,
                onDelete: () async {
                  try {
                    await _mediaService.deleteMedia(
                      docs[index].id,
                      data['storagePath'],
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('File deleted successfully'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      _showErrorSnackBar('Error deleting file: $e');
                    }
                  }
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showUploadOptions,
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      ),
    );
  }

  Future<void> _runBackfill() async {
    try {
      final result = await _mediaService.backfillThumbnailsForCurrentUser(
        mediaTypeFilter: 'image',
        maxItems: 50,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Backfill: processed ${result['processed']}, created ${result['created']}, skipped ${result['skipped']}, failed ${result['failed']}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Backfill failed: $e')));
      }
    }
  }
}
