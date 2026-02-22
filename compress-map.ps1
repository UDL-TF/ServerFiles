# PowerShell script to compress map files to bz2 and split if needed
param(
    [Parameter(Mandatory=$false)]
    [string]$MapFile
)

# Configuration
$SPLIT_THRESHOLD_BYTES = 26214400  # 25 MiB
$SPLIT_CHUNK_SIZE = 20MB  # 20 MiB in bytes

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# If no parameter provided, check if file was dragged
if (-not $MapFile) {
    if ($args.Count -gt 0) {
        $MapFile = $args[0]
    } else {
        Write-ColorOutput "Error: No map file provided" "Red"
        Write-Host "Usage: .\compress-map.ps1 <map_file.bsp>"
        Write-Host "Or drag and drop a .bsp file onto this script"
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# Validate file exists
if (-not (Test-Path $MapFile)) {
    Write-ColorOutput "Error: File not found: $MapFile" "Red"
    Read-Host "Press Enter to exit"
    exit 1
}

# Validate file extension
if (-not $MapFile.EndsWith(".bsp")) {
    Write-ColorOutput "Error: File must have .bsp extension" "Red"
    Read-Host "Press Enter to exit"
    exit 1
}

# Get absolute path
$MapFile = (Resolve-Path $MapFile).Path
$targetPath = "$MapFile.bz2"
$partsDir = "$targetPath.parts"

# Check if output already exists
if ((Test-Path $targetPath) -or (Test-Path $partsDir)) {
    Write-ColorOutput "Warning: Output already exists for $(Split-Path $MapFile -Leaf)" "Yellow"
    $response = Read-Host "Overwrite? (y/N)"
    if ($response -ne "y" -and $response -ne "Y") {
        Write-Host "Cancelled"
        Read-Host "Press Enter to exit"
        exit 0
    }
    if (Test-Path $targetPath) { Remove-Item $targetPath -Force }
    if (Test-Path $partsDir) { Remove-Item $partsDir -Recurse -Force }
}

Write-ColorOutput "Compressing $(Split-Path $MapFile -Leaf) to bzip2..." "Green"

# Check if bzip2 is available
$bzip2Path = Get-Command bzip2 -ErrorAction SilentlyContinue

if ($bzip2Path) {
    # Use bzip2 if available
    & bzip2 -ck $MapFile | Set-Content -Path $targetPath -Encoding Byte
} else {
    # Try to use 7-zip as fallback
    $7zipPaths = @(
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe",
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    )
    
    $7zipPath = $7zipPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    
    if ($7zipPath) {
        & $7zipPath a -tbzip2 $targetPath $MapFile | Out-Null
    } else {
        Write-ColorOutput "Error: Neither bzip2 nor 7-Zip found" "Red"
        Write-Host "Please install one of the following:"
        Write-Host "  - bzip2 (via chocolatey: choco install bzip2)"
        Write-Host "  - 7-Zip (https://www.7-zip.org/)"
        Read-Host "Press Enter to exit"
        exit 1
    }
}

Write-ColorOutput "✓ Created $targetPath" "Green"

# Check file size and split if needed
$fileSize = (Get-Item $targetPath).Length
$fileSizeMB = [math]::Round($fileSize / 1MB, 2)
Write-Host "Compressed size: $fileSizeMB MiB"

if ($fileSize -gt $SPLIT_THRESHOLD_BYTES) {
    Write-ColorOutput "File exceeds $SPLIT_THRESHOLD_BYTES bytes threshold" "Yellow"
    Write-ColorOutput "Splitting into 20 MiB chunks..." "Green"
    
    # Create parts directory
    New-Item -ItemType Directory -Path $partsDir -Force | Out-Null
    
    $baseName = Split-Path $targetPath -Leaf
    
    # Read and split the file
    $stream = [System.IO.File]::OpenRead($targetPath)
    $buffer = New-Object byte[] $SPLIT_CHUNK_SIZE
    $partNumber = 0
    
    try {
        while ($true) {
            $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
            if ($bytesRead -eq 0) { break }
            
            $partFile = Join-Path $partsDir ("{0}.part.{1:D3}" -f $baseName, $partNumber)
            [System.IO.File]::WriteAllBytes($partFile, $buffer[0..($bytesRead-1)])
            $partNumber++
        }
    }
    finally {
        $stream.Close()
    }
    
    # Remove the original compressed file
    Remove-Item $targetPath -Force
    
    Write-ColorOutput "✓ Split into $partNumber part(s) in $partsDir" "Green"
    
    # List the parts
    Write-Host "`nParts created:"
    Get-ChildItem $partsDir | ForEach-Object {
        $sizeMB = [math]::Round($_.Length / 1MB, 2)
        Write-Host "  $($_.Name) - $sizeMB MiB"
    }
} else {
    Write-ColorOutput "✓ File size is within threshold, no splitting needed" "Green"
}

Write-ColorOutput "`nDone!" "Green"

# Always pause at the end
Read-Host "Press Enter to exit"
