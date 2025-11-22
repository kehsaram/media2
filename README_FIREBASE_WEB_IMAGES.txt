Firebase Storage images on Web (Chrome) – Complete Guide

Overview
- Problem: Images load on Windows/Android but fail in Chrome. Cause is almost always missing CORS headers from Firebase Storage or using non-Firebase URLs (GCS console/JSON API links) that don’t work in browsers.
- This project includes code + steps that make images render reliably in Chrome, emulators, and production.

Quick start (TL;DR)
1) Set CORS on your Storage bucket one time (project media2-38118):
   - Open Google Cloud Console → Activate Cloud Shell → paste:
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

   - For production security, replace "*" with your domains (e.g., https://yourapp.com, http://localhost:5000).

2) Run on Chrome for development:
   - flutter run -d chrome
   - If you still see issues while waiting for CORS to propagate, try the HTML renderer: flutter run -d chrome --web-renderer html

3) Production deploy (Firebase Hosting example):
   - flutter build web
   - firebase init hosting (select the same Firebase project)
   - firebase deploy --only hosting
   - Keep the CORS policy on your bucket; hosting alone doesn’t fix CORS.

What this project changed in code (so Chrome works)
- Web image element: Added a WebImage widget that uses HtmlElementView to render a native <img> on the web. Files:
  - lib/widgets/web_image.dart
  - lib/widgets/web_image_stub.dart
  - lib/widgets/web_image_web.dart
- Smart URL resolution in lib/widgets/media_grid_item.dart:
  - Prefers storagePath -> getDownloadURL() for fresh, valid URLs
  - If only a saved URL exists, refresh via refFromURL(url).getDownloadURL()
  - Rehydrates GCS console/JSON-API links (storage.cloud.google.com / storage.googleapis.com) to real Firebase download URLs
  - Falls back to bytes or list-based matching when needed
- Full-screen preview now opens the ORIGINAL file (not just the thumbnail) and supports zooming.

Best practices for future projects
- Store storage paths, not just URLs
  - Save: uploadedBy, mediaType, uniqueFileName; compute storagePath = media/<uid>/<type>/<uniqueFileName>
  - Generate a fresh URL when you need it: FirebaseStorage.instance.ref(storagePath).getDownloadURL()
  - Saved downloadUrl tokens can expire; GCS console links are not the same as Firebase download URLs.

- Apply bucket CORS once per project
  - Minimum for images: GET, HEAD, OPTIONS with Access-Control-Allow-Origin
  - Consider setting origins explicitly in production instead of "*"

- Renderer note
  - CanvasKit (default) is stricter and requires correct CORS. The HTML renderer often avoids tainted-canvas problems but isn’t a substitute for CORS.

Testing matrix
- Windows desktop: flutter run -d windows
  - Not subject to browser CORS; good for functional tests, not for validating web image policies.
- Chrome (default CanvasKit): flutter run -d chrome
  - Realistic browser CORS behavior; validates bucket policy.
- Chrome (HTML renderer): flutter run -d chrome --web-renderer html
  - Useful while waiting for CORS propagation or diagnosing issues.
- Incognito test: try a clean profile to avoid cache/service worker effects.

Emulator notes
- If you use the Firebase Storage Emulator (optional), CORS is typically not enforced the same way as production. If your app connects to the production bucket from localhost, you still need the CORS policy on that bucket.
- To use emulators, connect explicitly in code (example only):
  - FirebaseStorage.instance.useStorageEmulator('localhost', 9199);
  - Do this only in debug dev builds. Not currently enabled in this project by default.

Verifying CORS is applied
- Cloud Shell: gsutil cors get gs://media2-38118.appspot.com
- Chrome DevTools → Network → select an image request:
  - Status 200, and response header includes: Access-Control-Allow-Origin: * (or your domain)
- If requests fail, read the Console for CORS errors (No 'Access-Control-Allow-Origin' header / tainted canvas).

Troubleshooting checklist
- Missing CORS headers
  - Re-run the gsutil cors set ... command. Wait 1–3 minutes and hard reload (Ctrl+Shift+R). Clear cache if needed.
- Wrong bucket
  - Confirm web storageBucket in lib/firebase_options.dart matches your real bucket: media2-38118.appspot.com
- Mixed content
  - Don’t load http images on an https site. Use https URLs only.
- Ad-blockers or extensions
  - Some block googleusercontent URLs. Test in Incognito with extensions disabled.
- Stale or GCS console URLs saved in Firestore
  - The code now rehydrates these, but best practice is to store storagePath and regenerate URLs.
- Service worker cache (Flutter web)
  - After builds, a stale service worker can cache old app code. Open chrome://serviceworker-internals and unregister, or run a hard refresh.
- 403/401 on getDownloadURL
  - If your Storage rules require auth, ensure the user is signed in on web as well, or make those objects publicly readable if that’s intended.

CORS templates you can reuse
- Wide open (dev):
  [
    {
      "origin": ["*"],
      "method": ["GET", "HEAD", "OPTIONS"],
      "responseHeader": ["Content-Type", "Access-Control-Allow-Origin"],
      "maxAgeSeconds": 3600
    }
  ]

- Restricted origins (prod):
  [
    {
      "origin": ["https://yourapp.com", "http://localhost:5000"],
      "method": ["GET", "HEAD", "OPTIONS"],
      "responseHeader": ["Content-Type", "Access-Control-Allow-Origin"],
      "maxAgeSeconds": 3600
    }
  ]

Deployment checklist for live sites
- CORS set on bucket as above
- Authorized domains in Firebase Auth include your web origin(s)
- Flutter web built with flutter build web (or your CI)
- Hosting/CDN configured (Firebase Hosting or your provider)
- Test in Incognito and a second browser to rule out cache/state

Included helper files in this repo
- README_CORS.md – short version of these steps
- fix_cors.ps1 – PowerShell helper that applies CORS if gsutil is installed locally
- lib/widgets/web_image* – web-native image rendering
- lib/widgets/media_grid_item.dart – robust URL resolution + full-screen original preview

FAQ
- Why did Windows work but Chrome didn’t? Desktop apps don’t enforce browser CORS.
- Do I still need CORS if I use the HTML renderer? It helps, but correct CORS is still required for a reliable production setup.
- Is using "*" for origin safe? It’s fine in dev; for production use your exact domains.

That’s all you need to reproduce this in future projects: set CORS once, store storagePath, generate URLs on demand, and (optionally) use a native <img> for web rendering.