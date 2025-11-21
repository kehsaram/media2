# 🔍 Visual CORS Troubleshooting Checklist

Use this checklist to quickly diagnose and fix image loading issues in Chrome.

## Step 1: Identify the Problem

### ✅ Check: Are you running on web?
```
Flutter Web? → YES → Continue to Step 2
Mobile App?  → YES → CORS not needed! Look elsewhere.
```

### ✅ Check: What do you see?
```
□ Placeholder icons instead of images
□ Broken image icons
□ Gray boxes where images should be
□ Spinners that never finish loading
```
**If ANY checked** → Likely CORS issue, continue to Step 2

## Step 2: Confirm It's CORS

### 🔍 Open Chrome DevTools
Press `F12` or `Ctrl+Shift+I` (Windows) or `Cmd+Option+I` (Mac)

### 🔍 Check Console Tab
Look for errors containing:
```
❌ "blocked by CORS policy"
❌ "No 'Access-Control-Allow-Origin' header"
❌ "CORS header 'Access-Control-Allow-Origin' missing"
```

**Found CORS error?** → ✅ Confirmed! Go to Step 3
**No CORS error?** → See "Not a CORS Issue" section below

### 🔍 Check Network Tab
1. Click "Network" tab
2. Filter by "Img"
3. Look at failed requests (red text)
4. Click on a failed request
5. Look at "Headers" → "Response Headers"

**Missing "access-control-allow-origin"?** → ✅ CORS issue confirmed!

## Step 3: Apply the Fix

### ⚡ Quick Fix (5 minutes)

#### Windows:
```cmd
✓ Open Command Prompt (as Admin)
✓ cd C:\path\to\media2
✓ gsutil cors set cors.json gs://media2-38118.appspot.com
✓ check_cors.bat
```

#### Mac/Linux:
```bash
✓ Open Terminal
✓ cd /path/to/media2
✓ gsutil cors set cors.json gs://media2-38118.appspot.com
✓ ./check_cors.sh
```

### Don't have gsutil?
```
□ Download Google Cloud SDK
  Windows: https://cloud.google.com/sdk/docs/install
  Mac/Linux: curl https://sdk.cloud.google.com | bash
  
□ Restart terminal
  
□ Login: gcloud auth login
  
□ Set project: gcloud config set project media2-38118
  
□ Try fix again
```

## Step 4: Verify the Fix

### 🧹 Clear Browser Cache
```
□ Press Ctrl+Shift+Delete (Windows) or Cmd+Shift+Delete (Mac)
□ Select "All time"
□ Check "Cached images and files"
□ Check "Cached images and files" 
□ Click "Clear data"
```

### 🔄 Hard Reload
```
□ Press Ctrl+Shift+R (Windows) or Cmd+Shift+R (Mac)
□ Or right-click refresh → "Empty Cache and Hard Reload"
```

### ✅ Test
```
□ Upload a new image
□ Does it show immediately? → ✅ FIXED!
□ Check DevTools Console (F12)
□ No CORS errors? → ✅ FIXED!
```

## Step 5: Confirm Success

### ✅ Success Indicators
```
✅ Images load immediately
✅ No errors in Console (F12)
✅ Network tab shows status "200 OK" for images
✅ No red requests in Network tab
✅ Images load in all browsers
```

## 📋 Not a CORS Issue? Check These:

### Issue: 401 Unauthorized
```
□ Sign out of the app
□ Sign back in
□ Try uploading a new image
□ Check Firebase Authentication is enabled
```

### Issue: 403 Forbidden
```
□ Check Firebase Storage Rules
□ Ensure rules allow read access
□ File location: storage.rules
□ Publish rules in Firebase Console
```

### Issue: 404 Not Found
```
□ Image was deleted
□ Wrong storage path
□ Re-upload the image
```

### Issue: Failed to fetch / Network error
```
□ Check internet connection
□ Check if firewall is blocking Firebase
□ Try on different network
□ Check Firebase Status: https://status.firebase.google.com/
```

### Issue: Images load on mobile but not web
```
□ THIS IS CORS! → Go to Step 3
```

### Issue: Slow loading
```
□ CORS probably not configured → Go to Step 2
□ Or large images need optimization
```

## 🔄 Checklist: Production Deployment

### Before Deploying to Production:
```
□ Update cors-production.json with your domain
□ Replace "yourdomain.com" with actual domain
□ Apply production CORS config
□ Test from production domain
□ Test from localhost (should fail - this is good!)
□ Verify CORS headers in Network tab
□ Clear cache and test again
□ Test in multiple browsers
```

## 🆘 Still Stuck? Get Help

### Gather This Information:
```
□ Output of: gsutil cors get gs://media2-38118.appspot.com
□ Screenshot of Console errors (F12)
□ Screenshot of Network tab (F12)
□ Browser version: chrome://version/
□ Operating system
□ What step you're stuck on
```

### Where to Get Help:
```
□ Check TROUBLESHOOTING_CHROME.md
□ Check CORS_SETUP.md for detailed steps
□ Check UNDERSTANDING_CORS.md to learn more
□ Open GitHub issue with information above
```

## 📱 Platform-Specific Quick Reference

### Windows Quick Commands
```cmd
# Check CORS
check_cors.bat

# Apply CORS
gsutil cors set cors.json gs://media2-38118.appspot.com

# Verify CORS
gsutil cors get gs://media2-38118.appspot.com
```

### Mac/Linux Quick Commands
```bash
# Check CORS
./check_cors.sh

# Apply CORS
gsutil cors set cors.json gs://media2-38118.appspot.com

# Verify CORS
gsutil cors get gs://media2-38118.appspot.com
```

### Alternative: Firebase Console
```
□ Go to: console.cloud.google.com
□ Select project: media2-38118
□ Navigate: Cloud Storage → Buckets
□ Click: media2-38118.appspot.com
□ Click: Configuration tab
□ Under: CORS configuration → Edit
□ Paste: Contents of cors.json
□ Click: Save
□ Wait: 2-3 minutes
□ Test: Clear cache and reload
```

## 🎯 Expected Timeline

```
✓ Reading this checklist: 5 minutes
✓ Identifying the issue: 2 minutes
✓ Installing gsutil (if needed): 10 minutes
✓ Applying CORS config: 2 minutes
✓ Verifying fix: 3 minutes
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Total: ~20 minutes (first time)
  Total: ~5 minutes (if gsutil installed)
```

## 💡 Pro Tips

```
✓ Always clear cache after CORS changes
✓ Test in incognito mode to avoid cache issues
✓ Wait 1-5 minutes for CORS changes to propagate
✓ Use check_cors scripts to verify configuration
✓ Keep browser DevTools open to see errors
✓ For production, restrict CORS to your domains
✓ CORS is one-time setup, works forever
```

---

**Need more details?** See [QUICK_FIX_GUIDE.md](QUICK_FIX_GUIDE.md)
**Want to understand CORS?** See [UNDERSTANDING_CORS.md](UNDERSTANDING_CORS.md)
**Stuck?** See [TROUBLESHOOTING_CHROME.md](TROUBLESHOOTING_CHROME.md)
