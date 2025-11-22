# Firebase Storage CORS Configuration Guide

## Problem
Images and other media files are not loading in Chrome (or other browsers) due to CORS (Cross-Origin Resource Sharing) restrictions. This is a common issue when accessing Firebase Storage resources from web applications.

## Solution
You need to configure CORS settings on your Firebase Storage bucket to allow browsers to fetch resources.

## ⚠️ Important: Choose the Right Configuration

This project includes TWO CORS configuration files:

1. **`cors.json`** - Development/Testing (allows all origins)
   - ✅ Use for: Local development, testing, getting started
   - ⚠️ Security: Allows ANY website to access your storage
   - 💡 Quick start configuration

2. **`cors-production.json`** - Production (restricted origins)
   - ✅ Use for: Production deployments
   - 🔒 Security: Only allows specific domains
   - 💡 Must update with your actual domain names

## Prerequisites
- Google Cloud SDK (gcloud CLI) installed
- Access to your Firebase project

## Setup Steps

### 1. Install Google Cloud SDK (if not already installed)

**Windows:**
- Download and run the installer: https://cloud.google.com/sdk/docs/install

**macOS:**
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
```

**Linux:**
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
```

### 2. Initialize gcloud and Authenticate

```bash
# Initialize gcloud
gcloud init

# Login to your Google account
gcloud auth login

# Set your project
gcloud config set project media2-38118
```

### 3. Apply CORS Configuration

**For Development/Testing:**
```bash
# Navigate to your project directory
cd /path/to/media2

# Apply the development CORS configuration (allows all origins)
gsutil cors set cors.json gs://media2-38118.appspot.com
```

**For Production:**
```bash
# 1. First, edit cors-production.json and replace "yourdomain.com" with your actual domain
# 2. Then apply the production CORS configuration
gsutil cors set cors-production.json gs://media2-38118.appspot.com
```

### 4. Verify CORS Configuration

```bash
# Check if CORS is properly configured
gsutil cors get gs://media2-38118.appspot.com
```

You should see output similar to:
```json
[
  {
    "origin": ["*"],
    "method": ["GET", "HEAD", "PUT", "POST", "DELETE"],
    "responseHeader": ["Content-Type", "Authorization", "Content-Length", "User-Agent", "X-Goog-Upload-Protocol", "X-Goog-Upload-Command"],
    "maxAgeSeconds": 3600
  }
]
```

## Alternative: Using Firebase Console

If you don't want to use the command line, you can also configure CORS through the Google Cloud Console:

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project (`media2-38118`)
3. Navigate to **Cloud Storage** → **Buckets**
4. Click on your bucket (`media2-38118.appspot.com`)
5. Go to the **Configuration** tab
6. Under **CORS configuration**, click **Edit**
7. Paste the contents of `cors.json` file
8. Click **Save**

## Understanding the CORS Configuration

The `cors.json` file contains:

- **origin**: `["*"]` - Allows requests from any origin (you can restrict this to specific domains for better security)
- **method**: Allowed HTTP methods
- **responseHeader**: Headers that browsers can access
- **maxAgeSeconds**: How long browsers can cache the CORS preflight response

## Security Considerations

For production, you should restrict the `origin` field to your specific domains:

```json
[
  {
    "origin": [
      "https://yourdomain.com",
      "https://www.yourdomain.com",
      "http://localhost:*"
    ],
    "method": ["GET", "HEAD"],
    "responseHeader": ["Content-Type"],
    "maxAgeSeconds": 3600
  }
]
```

## Using Verification Scripts

We've included helper scripts to verify CORS configuration:

**Unix/Mac:**
```bash
./check_cors.sh

# Or for a different bucket:
FIREBASE_STORAGE_BUCKET=gs://your-bucket.appspot.com ./check_cors.sh
```

**Windows:**
```cmd
check_cors.bat

REM Or for a different bucket:
set FIREBASE_STORAGE_BUCKET=gs://your-bucket.appspot.com
check_cors.bat
```

## Testing

After applying the CORS configuration:

1. Clear your browser cache (Ctrl+Shift+Delete in Chrome)
2. Hard refresh the page (Ctrl+Shift+R)
3. Open Developer Tools (F12)
4. Check the Console for any CORS errors
5. Check the Network tab to verify images are loading

## Troubleshooting

### Issue: "No such object" error
- Verify your bucket name is correct
- Ensure you're authenticated with the right Google account

### Issue: CORS errors persist
- Wait a few minutes for the configuration to propagate
- Clear browser cache completely
- Try in an incognito/private window

### Issue: Permission denied
- Make sure you have Owner or Editor role on the Firebase project
- Run: `gcloud auth application-default login`

### Issue: gsutil not found
- Ensure Google Cloud SDK is installed
- Restart your terminal after installation
- Add gsutil to your PATH

## Additional Resources

- [Firebase Storage CORS Documentation](https://firebase.google.com/docs/storage/web/download-files#cors_configuration)
- [Google Cloud Storage CORS Documentation](https://cloud.google.com/storage/docs/configuring-cors)
- [MDN CORS Documentation](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS)
