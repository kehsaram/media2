# Fix Web Images (CORS)

The issue is that Google Cloud Storage (Firebase Storage) blocks web browser requests by default for security (CORS).

## Solution 1: Run with HTML Renderer (Quickest Fix)
This bypasses the strict CORS checks by using standard HTML `<img>` tags instead of Canvas rendering.

Run this command in your terminal:
```powershell
flutter run -d chrome --web-renderer html
```

## Solution 2: Fix CORS Permanently (Recommended)
You need to tell Google Cloud to allow your app to access the images.

### Step 1: Open Cloud Shell
1. Go to [Google Cloud Console](https://console.cloud.google.com/).
2. Select your project: **media2-38118**.
3. Click the **Activate Cloud Shell** button (terminal icon in the top right toolbar).

### Step 2: Run the Fix Command
Copy and paste this **entire block** into the Cloud Shell and press Enter:

```bash
cat > cors.json <<EOF
[
    {
      "origin": ["*"],
      "method": ["GET", "HEAD", "PUT", "POST", "DELETE", "OPTIONS"],
      "responseHeader": ["Content-Type", "Access-Control-Allow-Origin", "Authorization", "Content-Length", "User-Agent", "x-goog-resumable"],
      "maxAgeSeconds": 3600
    }
]
EOF

gsutil cors set cors.json gs://media2-38118.appspot.com
```

### Step 3: Verify
Wait 1 minute, then reload your app in Chrome. The images should appear.
