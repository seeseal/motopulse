$token = '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'
$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}

$releaseId = '310654415'
$assetsUrl = "https://api.github.com/repos/seeseal/motopulse/releases/$releaseId/assets"
$assets = Invoke-RestMethod -Uri $assetsUrl -Headers $headers
foreach ($asset in $assets) {
    if ($asset.name -like "*.apk") {
        Write-Host "Deleting old asset: $($asset.name)"
        Invoke-RestMethod -Uri "https://api.github.com/repos/seeseal/motopulse/releases/assets/$($asset.id)" -Method DELETE -Headers $headers | Out-Null
    }
}

$apkPath = 'C:\Users\cecil\motopulse\build\app\outputs\flutter-apk\MotoPulse-v1.1.0.apk'
$uploadHeaders = $headers.Clone()
$uploadHeaders['Content-Type'] = 'application/vnd.android.package-archive'
$uploadUrl = "https://uploads.github.com/repos/seeseal/motopulse/releases/$releaseId/assets?name=MotoPulse-v1.1.0.apk"

$sizeMB = [math]::Round((Get-Item $apkPath).Length / 1MB, 1)
Write-Host "Uploading APK ($sizeMB MB)..."
$apkBytes = [System.IO.File]::ReadAllBytes($apkPath)
$response = Invoke-RestMethod -Uri $uploadUrl -Method POST -Headers $uploadHeaders -Body $apkBytes
Write-Host "Done! Download: $($response.browser_download_url)"
