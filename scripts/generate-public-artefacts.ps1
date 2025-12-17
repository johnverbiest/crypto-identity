$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$outputPath = Join-Path (Split-Path -Parent $scriptDir) "gpg\john-verbiest-public.asc"
echo "Public key export to $outputPath"
gpg --armor --export 3F17AE63F095712C | Out-File -FilePath $outputPath -Encoding ASCII
echo "Public key exported to $outputPath"

$outputPath = Join-Path (Split-Path -Parent $scriptDir) "identity.md"
echo "Resigning the identity file $outputPath"
Remove-Item "$outputPath.asc" -ErrorAction SilentlyContinue
gpg --detach-sign --armor $outputPath
echo "Resigned the identity file $outputPath"

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
