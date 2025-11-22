# PowerShell script to attempt CORS fix
Write-Host "Attempting to fix CORS for Firebase Storage..." -ForegroundColor Cyan

# Check for gsutil
if (Get-Command gsutil -ErrorAction SilentlyContinue) {
    Write-Host "gsutil found. Applying CORS rules..." -ForegroundColor Green
    gsutil cors set cors.json gs://media2-38118.appspot.com
    if ($?) {
        Write-Host "CORS rules applied successfully!" -ForegroundColor Green
    } else {
        Write-Host "Failed to apply CORS rules. Check permissions." -ForegroundColor Red
    }
} else {
    Write-Host "gsutil not found." -ForegroundColor Yellow
    Write-Host "Please install Google Cloud SDK or use the Cloud Console."
    Write-Host "See README_CORS.md for instructions."
}

Write-Host "Done."
