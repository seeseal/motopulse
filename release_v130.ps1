$token = $env:GITHUB_TOKEN  # set before running: $env:GITHUB_TOKEN = 'ghp_...'
$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}

# Create release
$releaseBody = "## What's new`n`n- OSRM road snapping: live GPS trace snapped to actual roads every 3 seconds`n- Bike marker rotates to face direction of travel`n- Heading-up navigation camera with 45 degree tilt (toggle between nav/north-up)`n- Speed-adaptive zoom: zooms out automatically at higher speeds`n- Smooth marker interpolation at 20fps`n`n## Download`n`nSideload MotoPulse-v1.3.0.apk directly on any Android device (arm64)."

$body = ConvertTo-Json @{
    tag_name = 'v1.3.0'
    name = 'v1.3.0 - Navigation Mode'
    body = $releaseBody
    draft = $false
    prerelease = $false
}

$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/seeseal/motopulse/releases' -Method POST -Headers $headers -Body $body -ContentType 'application/json'
Write-Host "Release created: $($release.html_url)"
Write-Host "Release ID: $($release.id)"

# Upload APK
$apkPath = 'C:\Users\cecil\motopulse\build\app\outputs\flutter-apk\MotoPulse-v1.3.0.apk'
$uploadHeaders = $headers.Clone()
$uploadHeaders['Content-Type'] = 'application/vnd.android.package-archive'
$uploadUrl = "https://uploads.github.com/repos/seeseal/motopulse/releases/$($release.id)/assets?name=MotoPulse-v1.3.0.apk"

$sizeMB = [math]::Round((Get-Item $apkPath).Length / 1MB, 1)
Write-Host "Uploading APK ($sizeMB MB)..."
$apkBytes = [System.IO.File]::ReadAllBytes($apkPath)
$response = Invoke-RestMethod -Uri $uploadUrl -Method POST -Headers $uploadHeaders -Body $apkBytes
Write-Host "Done! Download: $($response.browser_download_url)"
