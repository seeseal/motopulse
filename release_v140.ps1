$token = $env:GITHUB_TOKEN  # set before running: $env:GITHUB_TOKEN = 'ghp_...'
$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}

# Create release
$releaseBody = "## What's new`n`n- Background GPS keepalive rewritten with flutter_background_service (more reliable on Android)`n- Improved GPS settings: high accuracy, 5s interval, 10m distance filter (better battery life)`n- Crash detection rewritten as multi-signal state machine: requires impact >3.5g + pre-event speed >25 km/h + 15s post-impact immobility`n- Emergency countdown reduced from 30s to 15s`n- Google Geocoding API replaces Nominatim for faster, more accurate place search in route planner`n`n## Download`n`nSideload MotoPulse-v1.4.0.apk directly on any Android device (arm64)."

$body = ConvertTo-Json @{
    tag_name = 'v1.4.0'
    name = 'v1.4.0 - Crash Detection & Background GPS'
    body = $releaseBody
    draft = $false
    prerelease = $false
}

$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/seeseal/motopulse/releases' -Method POST -Headers $headers -Body $body -ContentType 'application/json'
Write-Host "Release created: $($release.html_url)"
Write-Host "Release ID: $($release.id)"

# Upload APK
$apkPath = 'C:\Users\cecil\motopulse\build\app\outputs\flutter-apk\MotoPulse-v1.4.0.apk'
$uploadHeaders = $headers.Clone()
$uploadHeaders['Content-Type'] = 'application/vnd.android.package-archive'
$uploadUrl = "https://uploads.github.com/repos/seeseal/motopulse/releases/$($release.id)/assets?name=MotoPulse-v1.4.0.apk"

$sizeMB = [math]::Round((Get-Item $apkPath).Length / 1MB, 1)
Write-Host "Uploading APK ($sizeMB MB)..."
$apkBytes = [System.IO.File]::ReadAllBytes($apkPath)
$response = Invoke-RestMethod -Uri $uploadUrl -Method POST -Headers $uploadHeaders -Body $apkBytes
Write-Host "Done! Download: $($response.browser_download_url)"
