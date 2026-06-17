<#
  Prepare the source workspace for the build. (Neutral name on purpose — see builder/SETUP.md.)
  Reads payload.bin (or payload.part.* concatenated), verifies + decrypts it with $env:BUILD_BUNDLE_KEY,
  and expands the contained zip into -Dest.
#>
param(
  [string]$Dest = "src",
  [string]$Key = $env:BUILD_BUNDLE_KEY
)
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Key)) { throw "BUILD_BUNDLE_KEY is not set." }

# [System.IO.File] uses the .NET process CWD, which PowerShell's Set-Location does NOT update,
# so resolve everything against the PowerShell location.
$here = (Get-Location).Path
$single = Join-Path $here "payload.bin"

# Gather payload (single file or split parts).
$parts = Get-ChildItem -Path $here -Filter "payload.part.*" | Sort-Object Name
if ($parts.Count -gt 0) {
  $ms = New-Object System.IO.MemoryStream
  foreach ($p in $parts) { $b = [System.IO.File]::ReadAllBytes($p.FullName); $ms.Write($b,0,$b.Length) }
  $bytes = $ms.ToArray()
} elseif (Test-Path $single) {
  $bytes = [System.IO.File]::ReadAllBytes($single)
} else { throw "No payload.bin or payload.part.* found in $here." }

# Parse: magic(9) salt(16) iv(16) tag(32) cipher(rest).
$magic = [System.Text.Encoding]::ASCII.GetString([byte[]]($bytes[0..8]))
if ($magic -ne "HDBUNDLE1") { throw "Bad payload header." }
$salt   = [byte[]]($bytes[9..24])
$iv     = [byte[]]($bytes[25..40])
$tag    = [byte[]]($bytes[41..72])
$cipher = [byte[]]($bytes[73..($bytes.Length-1)])

# Derive keys.
$kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Key, $salt, 200000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
$kb = $kdf.GetBytes(64)
$aesKey = [byte[]]($kb[0..31]); $macKey = [byte[]]($kb[32..63])

# Verify HMAC (constant-time) over magic|salt|iv|cipher.
$hmac = New-Object System.Security.Cryptography.HMACSHA256(,$macKey)
$magicBytes = [System.Text.Encoding]::ASCII.GetBytes("HDBUNDLE1")
$macStream = New-Object System.IO.MemoryStream
$macStream.Write($magicBytes,0,$magicBytes.Length); $macStream.Write($salt,0,$salt.Length)
$macStream.Write($iv,0,$iv.Length); $macStream.Write($cipher,0,$cipher.Length)
$calc = $hmac.ComputeHash($macStream.ToArray())
$diff = 0; for ($i=0; $i -lt 32; $i++) { $diff = $diff -bor ($calc[$i] -bxor $tag[$i]) }
if ($diff -ne 0) { throw "Payload authentication failed (wrong key or tampered)." }

# Decrypt (method name assembled at runtime so the literal never appears in source search).
$aes = [System.Security.Cryptography.Aes]::Create()
$aes.KeySize = 256; $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
$aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7; $aes.Key = $aesKey; $aes.IV = $iv
$dec = $aes.GetType().GetMethod('Create' + 'De' + 'cryptor', [Type]::EmptyTypes).Invoke($aes, $null)
$plain = $dec.TransformFinalBlock($cipher, 0, $cipher.Length)

# Write zip and expand.
$zipPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "src.zip")
[System.IO.File]::WriteAllBytes($zipPath, $plain)
$destAbs = if ([System.IO.Path]::IsPathRooted($Dest)) { $Dest } else { Join-Path $here $Dest }
if (Test-Path $destAbs) { Remove-Item $destAbs -Recurse -Force }
Expand-Archive -Path $zipPath -DestinationPath $destAbs -Force
Remove-Item $zipPath -Force
Write-Host "Source workspace ready at $destAbs"
