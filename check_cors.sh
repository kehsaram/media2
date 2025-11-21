#!/bin/bash

# Script to check if CORS is properly configured on Firebase Storage

echo "================================================"
echo "Firebase Storage CORS Configuration Checker"
echo "================================================"
echo ""

# Check if gsutil is installed
if ! command -v gsutil &> /dev/null; then
    echo "❌ ERROR: gsutil is not installed"
    echo ""
    echo "Please install Google Cloud SDK:"
    echo "  - macOS/Linux: curl https://sdk.cloud.google.com | bash"
    echo "  - Windows: https://cloud.google.com/sdk/docs/install"
    echo ""
    exit 1
fi

echo "✓ gsutil found"
echo ""

# Set bucket name
BUCKET="gs://media2-38118.appspot.com"

echo "Checking CORS configuration for: $BUCKET"
echo ""

# Try to get CORS configuration
CORS_CONFIG=$(gsutil cors get $BUCKET 2>&1)

if [ $? -eq 0 ]; then
    echo "✅ CORS is configured!"
    echo ""
    echo "Current CORS configuration:"
    echo "----------------------------"
    echo "$CORS_CONFIG"
    echo ""
    
    # Check if wildcard origin is present
    if echo "$CORS_CONFIG" | grep -q '"origin": \["\*"\]'; then
        echo "⚠️  WARNING: Using wildcard origin (*)"
        echo "   For production, restrict to specific domains"
        echo ""
    fi
    
    echo "✅ Your Firebase Storage is properly configured for web access"
    echo ""
else
    echo "❌ CORS is NOT configured or there was an error"
    echo ""
    echo "Error details:"
    echo "$CORS_CONFIG"
    echo ""
    echo "To fix this, run:"
    echo "  gsutil cors set cors.json $BUCKET"
    echo ""
    echo "See CORS_SETUP.md for detailed instructions"
    echo ""
    exit 1
fi

echo "================================================"
echo "Next steps:"
echo "1. Clear your browser cache (Ctrl+Shift+Delete)"
echo "2. Hard reload your app (Ctrl+Shift+R)"
echo "3. Check Chrome DevTools Console for errors"
echo "================================================"
