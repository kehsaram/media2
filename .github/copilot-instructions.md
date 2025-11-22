# Media2 Project Instructions

## Project Overview
This is a **Flutter** application for media storage and management, using **Firebase** as the backend (Auth, Firestore, Storage). It supports multiple platforms (Windows, Web, Android, iOS), with specific optimizations for Web and Windows.

## Architecture & Core Components
- **State Management**: Primarily uses `StreamBuilder` with Firestore streams and local `setState` for UI state.
- **Services**:
  - `AuthService` (`lib/services/auth_service.dart`): Handles Firebase Auth.
  - `MediaStorageService` (`lib/services/media_storage_service.dart`): Central logic for uploading, deleting, and retrieving media metadata. Handles platform differences (File vs Bytes).
- **UI Components**:
  - `MediaGridItem` (`lib/widgets/media_grid_item.dart`): Critical component for displaying media. Contains complex logic for URL resolution, thumbnail handling, and fallbacks for Web/CORS issues.
  - `HomeScreen`: Main dashboard with tabbed filtering.

## Key Patterns & Conventions

### 1. Web vs Native Handling
- **Platform Checks**: Use `kIsWeb` from `package:flutter/foundation.dart` to branch logic.
- **File Access**:
  - **Web**: Use `Uint8List` (bytes) for uploads and manipulation. Avoid `dart:io` `File` on web paths.
  - **Native**: Use `dart:io` `File`.
- **Image Loading (Web)**:
  - Due to CORS on Firebase Storage, `Image.network` often fails.
  - **Pattern**: `MediaGridItem` implements a fallback strategy:
    1. Try `storagePath` via Firebase SDK (auth-aware).
    2. Try `downloadUrl` / `thumbnailUrl`.
    3. Fallback to fetching bytes via HTTP or Storage SDK if standard rendering fails.
  - **Fix**: Ensure `cors.json` is applied to the Firebase Storage bucket if images block.

### 2. Media Uploads
- **Method**: `MediaStorageService.uploadMedia` (File) or `uploadMediaBytes` (Web).
- **Metadata**: Stored in Firestore `media` collection.
  - Fields: `fileName`, `uniqueFileName`, `downloadUrl`, `mediaType` (image, video, audio, document), `storagePath`, `thumbnailUrl`.
- **Thumbnails**: Generated client-side for images using `package:image`. Video thumbnails use `video_thumbnail` (native only) or placeholders.

### 3. Firestore Data Model
- **Collection**: `media`
- **Querying**: heavily relies on `uploadedBy` and `mediaType`.
- **Indexes**: Composite indexes may be required for filtering by type + sorting by date.

## Developer Workflow
- **Running**:
  - Web: `flutter run -d chrome --web-renderer html` (often helps with image rendering) or just `flutter run -d chrome`.
  - Windows: `flutter run -d windows`.
- **Debugging**:
  - Use `MediaGridItem`'s long-press diagnostic sheet to inspect URL sources and byte loading strategies.
  - Check `FIX_WEB_IMAGES.md` for CORS troubleshooting.

## Common Tasks
- **Adding a new media type**: Update `MediaStorageService.getSupportedMediaTypes`, `_getFileIcon`, and `_getTypeColor`.
- **Fixing broken images**: Check `MediaGridItem._resolveDownloadUrl` logic. It attempts to "rehydrate" old GCS console URLs (`storage.cloud.google.com`) into valid Firebase download URLs.
