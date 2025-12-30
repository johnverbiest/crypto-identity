$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$outputPath = Join-Path (Split-Path -Parent $scriptDir) "gpg\john-verbiest-public.asc"
echo "Public key export to $outputPath"
gpg --armor --export 3F17AE63F095712C | Out-File -FilePath $outputPath -Encoding ASCII
echo "Public key exported to $outputPath"

echo "Uploading public key to keys.openpgp.org"
try {
    $publicKey = Get-Content $outputPath -Raw
    echo "Key length: $($publicKey.Length) characters"
    
    # Manually construct JSON to ensure proper string encoding
    $escapedKey = [System.Text.RegularExpressions.Regex]::Escape($publicKey)
    $escapedKey = $publicKey.Replace('\', '\\').Replace('"', '\"').Replace("`r`n", '\n').Replace("`n", '\n').Replace("`r", '\n')
    $jsonBody = "{`"keytext`":`"$escapedKey`"}"
    echo "JSON body length: $($jsonBody.Length) bytes"
    
    echo "Sending POST request..."
    $response = Invoke-RestMethod -Uri "https://keys.openpgp.org/vks/v1/upload" `
        -Method Post `
        -Body $jsonBody `
        -ContentType "application/json" `
        -TimeoutSec 30 `
        -Verbose
    
    echo "Public key uploaded successfully to keys.openpgp.org"
    echo "Key fingerprint: $($response.key_fpr)"
    if ($response.token) {
        echo "Token: $($response.token)"
    }
    if ($response.status) {
        echo "Status: $($response.status | ConvertTo-Json)"
    }
} catch {
    echo "Error Type: $($_.Exception.GetType().FullName)"
    echo "Error Message: $($_.Exception.Message)"
    if ($_.Exception.Response) {
        echo "HTTP Status: $($_.Exception.Response.StatusCode) $($_.Exception.Response.StatusDescription)"
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            echo "Response Body: $responseBody"
        } catch {
            echo "Could not read response body"
        }
    }
    if ($_.ErrorDetails) {
        echo "Error Details: $($_.ErrorDetails.Message)"
    }
    echo "Full Error: $_"
}

$fingerprint = "E3FF2C5FE713C7DCA36C900993DE6C09D1FDC17C"
$qrCodePath = Join-Path (Split-Path -Parent $scriptDir) "gpg\fingerprint-qrcode.png"
echo "Generating QR code at $qrCodePath"

$qrCodeUrl = "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=OPENPGP4FPR:$fingerprint"
Invoke-WebRequest -Uri $qrCodeUrl -OutFile $qrCodePath
echo "QR code downloaded to $qrCodePath"

echo "Signing QR code"
Remove-Item "$qrCodePath.asc" -ErrorAction SilentlyContinue
gpg --detach-sign --armor $qrCodePath
echo "QR code signed"

$outputPath = Join-Path (Split-Path -Parent $scriptDir) "gpg\readme.md"
echo "Generating GPG readme at $outputPath"

$gpgReadmeContent = @"
# GPG Public Key

This directory contains the public OpenPGP key for John Verbiest.

## Key File

- [john-verbiest-public.asc](john-verbiest-public.asc) - ASCII armored public key

## Key Fingerprint

``````
$fingerprint
``````

## QR Code

Scan this QR code with OpenKeychain or other compatible apps to import the key:

![QR Code for GPG Key](fingerprint-qrcode.png)

The QR code contains: ``OPENPGP4FPR:$fingerprint``

**Verification:** [fingerprint-qrcode.png.asc](fingerprint-qrcode.png.asc)

## Import Key

To import this key into your GPG keyring:

``````bash
gpg --import john-verbiest-public.asc
``````

Or download directly from a keyserver:

``````bash
gpg --recv-keys $fingerprint
``````

## Verify Key

The key is also available on [keys.openpgp.org](https://keys.openpgp.org/search?q=$fingerprint).
"@

$gpgReadmeContent | Out-File -FilePath $outputPath -Encoding UTF8 -NoNewline
echo "GPG readme generated at $outputPath"

$outputPath = Join-Path (Split-Path -Parent $scriptDir) "identity.md"
echo "Resigning the identity file $outputPath"
Remove-Item "$outputPath.asc" -ErrorAction SilentlyContinue
gpg --detach-sign --armor $outputPath
echo "Resigned the identity file $outputPath"

$outputPath = Join-Path (Split-Path -Parent $scriptDir) "identity.pdf"
if (Test-Path $outputPath) {
    echo "Resigning the identity PDF $outputPath"
    Remove-Item "$outputPath.asc" -ErrorAction SilentlyContinue
    gpg --detach-sign --armor $outputPath
    echo "Resigned the identity PDF $outputPath"
} else {
    echo "Warning: identity.pdf not found, skipping signature"
}

$outputPath = Join-Path (Split-Path -Parent $scriptDir) "ssh\ssh_auth_keys.pub"
echo "Exporting SSH public keys to $outputPath"

# Get all authentication subkeys from the key (get last 8 chars as short key ID)
$activeSubkeys = @{}
gpg --with-colons --list-keys 3F17AE63F095712C | Select-String "^sub:.*:a:" | ForEach-Object {
    $fields = $_ -split ":"
    $fullKeyId = $fields[4]
    $shortKeyId = $fullKeyId.Substring($fullKeyId.Length - 8).ToUpper()
    $activeSubkeys[$shortKeyId] = $fullKeyId
}

if ($activeSubkeys.Count -eq 0) {
    echo "Warning: No authentication subkeys found"
} else {
    echo "Found $($activeSubkeys.Count) active authentication subkey(s)"
    
    # Read existing SSH keys and filter out removed subkeys
    $existingKeys = @{}
    if (Test-Path $outputPath) {
        Get-Content $outputPath | ForEach-Object {
            if ($_ -match 'openpgp:0x([A-F0-9]{8})') {
                $shortKeyId = $matches[1]
                if ($activeSubkeys.ContainsKey($shortKeyId)) {
                    $existingKeys[$shortKeyId] = $_
                    echo "Keeping existing SSH key for subkey 0x$shortKeyId"
                } else {
                    echo "Removing SSH key for inactive subkey 0x$shortKeyId"
                }
            }
        }
    }
    
    # Export missing subkeys
    $finalKeys = @()
    foreach ($shortKeyId in $activeSubkeys.Keys) {
        if ($existingKeys.ContainsKey($shortKeyId)) {
            $finalKeys += $existingKeys[$shortKeyId]
        } else {
            $fullKeyId = $activeSubkeys[$shortKeyId]
            echo "Exporting new SSH key for subkey 0x$shortKeyId"
            $sshKey = (gpg --export-ssh-key $fullKeyId 2>$null | Out-String).Trim()
            if ($sshKey) {
                $finalKeys += $sshKey
            }
        }
    }
    
    # Write all keys to file
    if ($finalKeys.Count -gt 0) {
        ($finalKeys -join "`n") | Out-File -FilePath $outputPath -Encoding ASCII -NoNewline
        echo "Saved $($finalKeys.Count) SSH public key(s) to $outputPath"
    }
}

if (Test-Path $outputPath) {
    echo "Resigning SSH public keys file $outputPath"
    Remove-Item "$outputPath.asc" -ErrorAction SilentlyContinue
    gpg --detach-sign --armor $outputPath
    echo "Resigned SSH public keys file $outputPath"
}

$outputPath = Join-Path (Split-Path -Parent $scriptDir) "README.md"
echo "Generating README.md at $outputPath"

$readmeContent = @"
# Crypto Identity

This repository contains the cryptographic identity information for John Verbiest.

## Documents

- [Identity Statement](identity.md) - Main identity document with OpenPGP key fingerprint
- [Identity Statement (PDF)](identity.pdf) - PDF version of the identity statement
- [SSH Public Keys Setup](ssh/readme.md) - Instructions for importing SSH public keys

## Verification

All documents in this repository are cryptographically signed and can be verified using the GPG key found in the [gpg](gpg/) directory.
"@

$readmeContent | Out-File -FilePath $outputPath -Encoding UTF8 -NoNewline
echo "README.md generated at $outputPath"
