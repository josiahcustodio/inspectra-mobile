# Publishes a new tablet update: .\release.ps1 "What changed"
# Builds whatever is in the working tree, uploads it to GitHub Releases, then
# bumps the build number in pubspec.yaml. Tablets on Wi-Fi see the prompt on
# their next check.
param([Parameter(Mandatory = $true)][string]$Notes)
$ErrorActionPreference = 'Stop'

$repo = 'josiahcustodio/inspectra-releases'
$pubspecPath = "$PSScriptRoot\pubspec.yaml"
$pubspec = [IO.File]::ReadAllText($pubspecPath)
if ($pubspec -notmatch '(?m)^version: (\d+\.\d+\.\d+)\+(\d+)') { throw 'No version line in pubspec.yaml' }
$version = $Matches[1]
$build = [int]$Matches[2] + 1
$tag = "v$version-b$build"

Set-Location $PSScriptRoot
# One APK per CPU type: less than half the download of a universal APK.
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --build-number=$build --dart-define=APP_BUILD=$build
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

$out = "$PSScriptRoot\build\release-upload"
New-Item -ItemType Directory -Force $out | Out-Null
Remove-Item "$out\*" -Force

$apks = @{}
foreach ($abi in 'arm64-v8a', 'armeabi-v7a') {
    $name = "inspectra-$abi.apk"
    Copy-Item "$PSScriptRoot\build\app\outputs\flutter-apk\app-$abi-release.apk" "$out\$name"
    $apks[$abi] = @{
        url       = "https://github.com/$repo/releases/download/$tag/$name"
        sha256    = (Get-FileHash "$out\$name" -Algorithm SHA256).Hash.ToLower()
        megabytes = [int][math]::Ceiling((Get-Item "$out\$name").Length / 1MB)
    }
}

$manifest = @{ build = $build; version = $version; notes = $Notes; apks = $apks } | ConvertTo-Json -Depth 3
# WriteAllText, not Set-Content: PowerShell 5.1 adds a BOM that breaks JSON parsers.
[IO.File]::WriteAllText("$out\update.json", $manifest)

gh release create $tag "$out\inspectra-arm64-v8a.apk" "$out\inspectra-armeabi-v7a.apk" "$out\update.json" -R $repo --title "Inspectra $version (build $build)" --notes $Notes --latest
if ($LASTEXITCODE -ne 0) { throw 'gh release create failed' }

# Last, so a failed build or upload does not burn a build number.
[IO.File]::WriteAllText($pubspecPath, ($pubspec -replace '(?m)^version: .*?(\r?)$', "version: $version+$build`$1"))
Write-Host "Published $tag. Commit pubspec.yaml to keep the build number."
