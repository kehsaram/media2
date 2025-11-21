# media2

A Flutter-based media storage application with Firebase integration.

## 🚨 Images Not Loading in Chrome? **START HERE** 👇

If images are not loading in your web browser, you need to configure CORS. This is a **5-minute fix**:

### ⚡ Quick Fix
1. Install Google Cloud SDK: https://cloud.google.com/sdk/docs/install
2. Run these commands:
   ```bash
   gcloud auth login
   gcloud config set project media2-38118
   cd /path/to/media2
   gsutil cors set cors.json gs://media2-38118.appspot.com
   ```
3. Clear browser cache (Ctrl+Shift+Delete)
4. Reload your app (Ctrl+Shift+R)

**✅ Images should now load!**

## 📚 Documentation

| Guide | Description |
|-------|-------------|
| **[QUICK_FIX_GUIDE.md](QUICK_FIX_GUIDE.md)** | 5-minute fix for image loading issues |
| **[CORS_SETUP.md](CORS_SETUP.md)** | Complete CORS configuration guide |
| **[TROUBLESHOOTING_CHROME.md](TROUBLESHOOTING_CHROME.md)** | Advanced debugging for Chrome issues |
| **[UNDERSTANDING_CORS.md](UNDERSTANDING_CORS.md)** | Learn why CORS is needed and how it works |
| **[README_SETUP.md](README_SETUP.md)** | Complete Firebase setup and app configuration |

## 🔧 Helpful Scripts

- **Windows:** Run `check_cors.bat` to verify CORS configuration
- **Mac/Linux:** Run `./check_cors.sh` to verify CORS configuration

## Quick Start

1. **Setup Firebase:** See [README_SETUP.md](README_SETUP.md)
2. **Fix CORS (Web only):** See [QUICK_FIX_GUIDE.md](QUICK_FIX_GUIDE.md)
3. **Run the app:** `flutter run`
