# Chrome/Web Browser Image Loading Issues - Troubleshooting Guide

## Common Symptoms

1. ✗ Images show placeholder icons instead of actual images
2. ✗ Console shows CORS errors: "Access to fetch at '...' has been blocked by CORS policy"
3. ✗ Images load fine on mobile apps but not on web
4. ✗ Network tab shows failed requests with CORS errors

## Root Causes & Solutions

### 1. CORS Not Configured (Most Common)

**Problem:** Firebase Storage bucket doesn't have CORS configuration.

**Solution:**
```bash
# Apply CORS configuration
gsutil cors set cors.json gs://media2-38118.appspot.com
```

See [CORS_SETUP.md](CORS_SETUP.md) for detailed instructions.

### 2. Browser Cache Issues

**Problem:** Browser is caching old failed requests.

**Solution:**
```
1. Open Chrome DevTools (F12)
2. Right-click on the refresh button
3. Select "Empty Cache and Hard Reload"
4. Or use Ctrl+Shift+Delete to clear all cache
```

### 3. Firebase Authentication Token Issues

**Problem:** Download URLs have expired tokens.

**Solution:**
The app already handles this by:
- Refreshing URLs using `getDownloadURL()` from Firebase SDK
- Trying multiple fallback methods
- Using Storage SDK's `getData()` as a fallback

If still failing:
1. Sign out and sign back in
2. Re-upload the images

### 4. Network Policy Restrictions

**Problem:** Corporate firewall or network policy blocking requests.

**Solution:**
- Try on a different network (mobile hotspot)
- Check if your network allows Firebase Storage domain
- Contact IT if on corporate network

### 5. Browser Extensions Blocking Requests

**Problem:** Ad blockers or privacy extensions blocking Firebase requests.

**Solution:**
1. Try in Incognito/Private mode
2. Disable extensions temporarily
3. Whitelist Firebase domains:
   - `*.googleapis.com`
   - `*.firebaseapp.com`
   - `*.appspot.com`

### 6. Invalid Storage Bucket Configuration

**Problem:** Storage bucket name or configuration is incorrect.

**Solution:**
Check `firebase_options.dart`:
```dart
storageBucket: 'media2-38118.appspot.com',
```

Ensure this matches your Firebase project's storage bucket.

### 7. HTTP vs HTTPS Mixed Content

**Problem:** Trying to load HTTPS resources from HTTP page.

**Solution:**
- Always run the web app on HTTPS in production
- For local development: `flutter run -d chrome --web-port=8080`

## Debugging Steps

### Step 1: Check Console Errors
```
1. Open Chrome DevTools (F12)
2. Go to Console tab
3. Look for red errors mentioning "CORS" or "Access-Control-Allow-Origin"
```

### Step 2: Check Network Requests
```
1. Open DevTools → Network tab
2. Filter by "Img" or "XHR"
3. Click on a failed request
4. Check the "Headers" tab for CORS headers
5. Look for these headers in the Response:
   - access-control-allow-origin
   - access-control-allow-methods
```

### Step 3: Verify Firebase Storage Access
```
1. Go to Firebase Console
2. Navigate to Storage
3. Try to download an image manually
4. If manual download works, it's a CORS issue
```

### Step 4: Test with Direct URL
```
1. Get a Firebase Storage download URL
2. Paste it directly in browser
3. If it downloads, CORS is the issue
4. If it doesn't work, check Firebase Auth/Rules
```

## Testing After CORS Configuration

### 1. Wait for Propagation
CORS changes can take 1-5 minutes to propagate. Be patient!

### 2. Clear Everything
```bash
# Clear browser data
1. Ctrl+Shift+Delete
2. Select "All time"
3. Check "Cached images and files"
4. Clear data

# Or use incognito mode
Ctrl+Shift+N (Chrome)
```

### 3. Verify CORS is Applied
```bash
gsutil cors get gs://media2-38118.appspot.com
```

Should return your CORS configuration.

### 4. Test Image Loading
1. Reload the app
2. Upload a new image
3. Check if it displays immediately
4. Check console for errors

## Production Checklist

Before deploying to production:

- [ ] CORS configuration applied to Firebase Storage
- [ ] Firebase Storage Rules published
- [ ] Firestore Rules published
- [ ] Authentication enabled
- [ ] HTTPS enabled for production domain
- [ ] CORS origin restricted to your domain (not wildcard `*`)
- [ ] Tested in multiple browsers (Chrome, Firefox, Safari, Edge)
- [ ] Tested on mobile browsers
- [ ] Tested with and without browser extensions

## Advanced Debugging

### Enable Verbose Logging in Flutter Web
```bash
flutter run -d chrome --verbose
```

### Check Network Waterfall
In DevTools → Network:
1. Look at the timing of requests
2. Check if requests are being blocked before they start
3. Look for 401, 403, or 0 status codes

### Use curl to Test CORS
```bash
curl -H "Origin: http://localhost" \
     -H "Access-Control-Request-Method: GET" \
     -H "Access-Control-Request-Headers: X-Requested-With" \
     -X OPTIONS --verbose \
     "YOUR_FIREBASE_STORAGE_URL"
```

### Check Firebase Storage Logs
1. Go to Google Cloud Console
2. Navigate to Logging
3. Filter by "storage.googleapis.com"
4. Look for denied requests

## Still Not Working?

If you've tried everything above:

1. **Re-check CORS configuration:**
   ```bash
   gsutil cors set cors.json gs://media2-38118.appspot.com
   gsutil cors get gs://media2-38118.appspot.com
   ```

2. **Verify Firebase project:**
   - Ensure you're using the correct project
   - Check billing is enabled (required for some features)
   - Verify Storage is enabled

3. **Try a different browser:**
   - Test in Firefox, Edge, or Safari
   - This helps identify browser-specific issues

4. **Check Firebase Status:**
   - Visit https://status.firebase.google.com/
   - Look for any ongoing incidents

5. **Create a minimal test case:**
   - Try loading ONE image URL directly in browser
   - If that fails, focus on Firebase configuration
   - If that works, focus on app code

## Getting Help

If still stuck, gather this information:

1. **Console errors** (full error messages)
2. **Network tab screenshot** (showing failed requests)
3. **CORS configuration** (`gsutil cors get gs://...`)
4. **Browser and version** (e.g., Chrome 120.0.6099.109)
5. **Flutter version** (`flutter --version`)

Then ask for help on:
- [StackOverflow](https://stackoverflow.com/questions/tagged/firebase-storage+cors)
- [Firebase Support](https://firebase.google.com/support)
- GitHub Issues for this project
