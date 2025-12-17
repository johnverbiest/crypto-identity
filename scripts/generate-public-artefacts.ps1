$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$outputPath = Join-Path (Split-Path -Parent $scriptDir) "gpg\john-verbiest-public.asc"
echo "Public key export to $outputPath"
gpg --armor --export 3F17AE63F095712C > $outputPath
echo "Public key exported to $outputPath"

$outputPath = Join-Path (Split-Path -Parent $scriptDir) "identity.md"
echo "Resigning the identity file $outputPath"
// delete existing signature if any
Remove-Item "$outputPath.asc" -ErrorAction SilentlyContinue
gpg --detach-sign --armor $outputPath
echo "Resigned the identity file $outputPath"

$outputPath = Join-Path (Split-Path -Parent $scriptDir) "ssh\ssh_auth_keys.pub"
echo "Exporting SSH public key to $outputPath"
gpg --export-ssh-key 3F17AE63F095712C > $outputPath
echo "SSH public key exported to $outputPath"
