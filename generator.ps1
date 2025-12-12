# ------------------------------------------------------------
#  Utility: GZip compression (compatible with pako.inflate)

#NEEDS QRCoder.dll for .NET 4.0 in same folder or path
#https://www.nuget.org/packages/QRCoder

#read data at https://airgapped-qr-code-transfer.mohanram.co.in/scanner
#A powershell fork of airgapped-qr-code-generator. Images are displayed entirely in the CLI.
#most suitable on windows computers with policies that severly restricts browsers and software installtions. 

#Do not use this software for espionage or cyber crime :/

#Useage:
#C:\path\generator.ps1 `
#    -FilePath "C:\path\filetoSend.png" `
#    -VerticalScale 1 `
#    -HorizontalScale 1 `
#    -DarkChar "." `
#    -LightChar "#" `
#	-ChunkSize 150`
#	-ChunkDelayMs 100
	
	


# ------------------------------------------------------------
param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    # ASCII rendering options
    [int]$HorizontalScale = 4,   # how many chars per module horizontally
    [int]$VerticalScale   = 2,   # how many times to repeat each rendered line

    # Defaults as you suggested
    [string]$DarkChar  = ".",
    [string]$LightChar = "#",

    # Compressed bytes per QR chunk (same as generator.html)
    [int]$ChunkSize = 120,

    # Display timing (in milliseconds)
    [int]$ChunkDelayMs    = 100,
    [int]$MetadataDelayMs = 1000,

    # Path to QRCoder.dll (if omitted, we try QRCoder.dll next to the script)
    [string]$QRCoderDllPath
)

if ($HorizontalScale -lt 1 -or $VerticalScale -lt 1) {
    throw "HorizontalScale and VerticalScale must be >= 1."
}
if ($ChunkSize -lt 1) {
    throw "ChunkSize must be >= 1."
}

# ------------------------------------------------------------
#  Load QRCoder (DLL must be present somewhere you specify)
# ------------------------------------------------------------

if (-not $QRCoderDllPath -or [string]::IsNullOrWhiteSpace($QRCoderDllPath)) {
    if ($PSScriptRoot) {
        $QRCoderDllPath = Join-Path $PSScriptRoot 'QRCoder.dll'
    } else {
        $QRCoderDllPath = 'QRCoder.dll'
    }
}

if (-not ("QRCoder.QRCodeGenerator" -as [type])) {
    if (-not (Test-Path $QRCoderDllPath)) {
        throw "QRCoder.dll not found. Specify -QRCoderDllPath or copy QRCoder.dll next to this script. Current path: $QRCoderDllPath"
    }
    Add-Type -Path $QRCoderDllPath
}

# Reuse a single generator instance
$script:QrGenerator = New-Object QRCoder.QRCodeGenerator

# ------------------------------------------------------------
#  Utility: GZip compression (compatible with pako.inflate)
# ------------------------------------------------------------
function Compress-GzipBytes {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Data
    )

    $ms = New-Object System.IO.MemoryStream
    try {
        $gzip = New-Object System.IO.Compression.GZipStream(
            $ms,
            [System.IO.Compression.CompressionMode]::Compress
        )
        try {
            $gzip.Write($Data, 0, $Data.Length)
        }
        finally {
            $gzip.Dispose()
        }
        return $ms.ToArray()
    }
    finally {
        $ms.Dispose()
    }
}

# ------------------------------------------------------------
#  encode_data(index, bytes)  (mirror of generator.html)
#
#  JS:
#    encoded_string = String.fromCharCode.apply(null, input_bytes)
#    utf8_bytes     = new TextEncoder().encode(encoded_string)
#    encoded_data   = btoa(String.fromCharCode.apply(null, utf8_bytes))
#    return index + "," + encoded_data
# ------------------------------------------------------------
function Encode-ChunkString {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Index,

        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    # 1) bytes -> string whose char codes are those bytes
    $chars = New-Object char[] $Bytes.Length
    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        $chars[$i] = [char]$Bytes[$i]
    }
    $encodedString = -join $chars

    # 2) UTF‑8 bytes of that string (like TextEncoder in JS)
    $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($encodedString)

    # 3) base64 of UTF‑8 bytes
    $b64 = [System.Convert]::ToBase64String($utf8Bytes)

    # 4) "index,base64"
    return "$Index,$b64"
}

# ------------------------------------------------------------
#  Render a payload as ASCII QR using QRCoder.ASCIIQRCode
# ------------------------------------------------------------
function Show-QrPayload {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Payload,

        [int]$HorizontalScale,
        [int]$VerticalScale,
        [string]$DarkChar,
        [string]$LightChar
    )

    $eccLevel = [QRCoder.QRCodeGenerator+ECCLevel]::M

    # Create QRCodeData
    $qrData = $script:QrGenerator.CreateQrCode($Payload, $eccLevel)
    try {
        # Use built-in ASCII renderer with *no* internal scaling:
        # repeatPerModule = 1
        $asciiRenderer = New-Object QRCoder.ASCIIQRCode($qrData)
        try {
            $baseQr = $asciiRenderer.GetGraphic(
                1,          # repeatPerModule (we'll scale ourselves)
                $DarkChar,  # dark module
                $LightChar, # light module
                $true,      # drawQuietZones
                "`n"        # newline
            )
        }
        finally {
            if ($asciiRenderer -is [System.IDisposable]) {
                $asciiRenderer.Dispose()
            }
        }
    }
    finally {
        if ($qrData -is [System.IDisposable]) {
            $qrData.Dispose()
        }
    }

    Clear-Host

    # Now apply *our* scaling horizontally and vertically
    $baseLines = $baseQr -split "`n"

    foreach ($line in $baseLines) {

        # Horizontal scaling: repeat each character
        if ($HorizontalScale -gt 1) {
            $sb = New-Object System.Text.StringBuilder
            foreach ($ch in $line.ToCharArray()) {
                for ($hx = 0; $hx -lt $HorizontalScale; $hx++) {
                    [void]$sb.Append($ch)
                }
            }
            $scaledLine = $sb.ToString()
        }
        else {
            $scaledLine = $line
        }

        # Vertical scaling: repeat each line
        for ($v = 0; $v -lt $VerticalScale; $v++) {
            Write-Host $scaledLine
        }
    }
}

# ------------------------------------------------------------
#  Main logic (matches generator.html semantics)
# ------------------------------------------------------------

if (-not (Test-Path $FilePath)) {
    throw "File not found: $FilePath"
}

# Read raw bytes of the file
[byte[]]$fileBytes = [System.IO.File]::ReadAllBytes($FilePath)

# GZip compress; pako.inflate on the JS side will decompress this
[byte[]]$gzBytes = Compress-GzipBytes -Data $fileBytes

$len         = $gzBytes.Length
$totalChunks = [int][Math]::Ceiling($len / [double]$ChunkSize)

# Build metadata frame: {"name":"...","chunks":N}
$fileName = [System.IO.Path]::GetFileName($FilePath)
$metaObj  = [PSCustomObject]@{
    name   = $fileName
    chunks = $totalChunks
}
$metaJson = $metaObj | ConvertTo-Json -Compress

# --- Show metadata QR (first frame, as generator.html does) ---
Show-QrPayload -Payload $metaJson `
               -HorizontalScale $HorizontalScale `
               -VerticalScale   $VerticalScale `
               -DarkChar        $DarkChar `
               -LightChar       $LightChar

Write-Host ""
Write-Host "Metadata frame (file name & chunk count)."
Start-Sleep -Milliseconds $MetadataDelayMs

# --- Show each data chunk as a QR frame ---
for ($i = 0; $i -lt $totalChunks; $i++) {

    $start = $i * $ChunkSize
    $count = [Math]::Min($ChunkSize, $len - $start)

    [byte[]]$chunk = New-Object byte[] $count
    [Array]::Copy($gzBytes, $start, $chunk, 0, $count)

    $payload = Encode-ChunkString -Index $i -Bytes $chunk

    Show-QrPayload -Payload $payload `
                   -HorizontalScale $HorizontalScale `
                   -VerticalScale   $VerticalScale `
                   -DarkChar        $DarkChar `
                   -LightChar       $LightChar

    Write-Host ""
    Write-Host ("Transferring chunk {0}/{1} ..." -f ($i + 1), $totalChunks)

    Start-Sleep -Milliseconds $ChunkDelayMs
}

Write-Host ""
Write-Host "All frames sent. Scanner should reconstruct the file and prompt to download."
