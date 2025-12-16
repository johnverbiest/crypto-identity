$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputPath = Join-Path (Split-Path -Parent $scriptDir) "gpg\john-verbiest-public.asc"
gpg --armor --export 3F17AE63F095712C > $outputPath
echo "Public key exported to $outputPath"


$outputPath = Join-Path (Split-Path -Parent $scriptDir) "identity.md"
gpg --detach-sign --armor $outputPath
