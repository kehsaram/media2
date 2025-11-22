# Fixing Image Loading on Chrome (Permanent CORS fix)

If images are not loading in Chrome but work on Windows/Android, the issue is almost always **Cross-Origin Resource Sharing (CORS)** on your Firebase Storage bucket. Flutter Web (especially CanvasKit) draws images on a WebGL/canvas and the browser requires the storage server to send `Access-Control-Allow-Origin` headers.

This guide sets a permanent CORS policy on your bucket and provides quick workarounds while you apply it.

Bucket name for this project: `media2-38118.appspot.com` (see lib/firebase_options.dart)

## A. Permanent fix (recommended)

Use Google Cloud Console + Cloud Shell (no local tools required):

1) Open: https://console.cloud.google.com/ and select project `media2-38118`
2) Click the terminal icon (Activate Cloud Shell)
3) Paste the following and press Enter:

```bash
cat > cors.json <<'EOF'
[
  {
    "origin": ["*"],
    "method": ["GET", "HEAD", "OPTIONS"],
    "responseHeader": [
      "Content-Type",
      "Access-Control-Allow-Origin",
      "Access-Control-Allow-Headers",
      "Authorization",
      "Content-Length",
      "x-goog-resumable"
    ],
    "maxAgeSeconds": 3600
  }
]
EOF

gsutil cors set cors.json gs://media2-38118.appspot.com
gsutil cors get gs://media2-38118.appspot.com
```

Notes:
- `origin: ["*"]` is simplest. For stricter security, replace with your domains like `https://your-domain.com`, `http://localhost:5000`.
- Only `GET, HEAD, OPTIONS` are needed to display images.

Propagation usually takes 1–3 minutes. Clear the browser cache and reload.

## B. Quick dev workaround (while waiting)

Flutter HTML renderer avoids Canvas tainting and often works even when CORS is missing:

```powershell
flutter run -d chrome --web-renderer html
```

## C. What we changed in code

- Added a web-specific image widget that uses a native `<img>` element (HtmlElementView) for web, reducing CORS friction.
- Implemented robust URL rehydration for GCS URLs (storage.cloud.google.com or JSON API links) to proper Firebase download URLs.

Files:
- lib/widgets/web_image.dart
- lib/widgets/web_image_stub.dart
- lib/widgets/web_image_web.dart
- lib/widgets/media_grid_item.dart (uses WebImage on web)

## D. Verify
1) Run your app in Chrome
2) Long-press a tile -> Diagnostics shows the URL/byte source used
3) Images should render; if not, confirm CORS with `gsutil cors get` above
