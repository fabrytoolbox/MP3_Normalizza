# normalizza.ps1 - v2.0.0
# Normalizza il volume MP3 con loudnorm EBU R128
# PRESERVA tutti i tag ID3, copertine e metadati
# Crea SEMPRE un file di log nella cartella di output
#
# Modalita interattiva (guidata):
#   .\normalizzaV2_beta.ps1
#
# Setup ambiente (scarica FFmpeg in .\tools\ffmpeg):
#   .\normalizzaV2_beta.ps1 -Setup
#
# Diretto con profilo per-auto:
#   .\normalizzaV2_beta.ps1 -InputPath "C:\Musica" -Preset per-auto -Bitrate 320k
#
# Dry-run (analisi senza modificare nulla):
#   .\normalizzaV2_beta.ps1 -InputPath "C:\Musica" -Preset per-auto -DryRun
#
# Dry-run ricorsivo (include sottocartelle):
#   .\normalizzaV2_beta.ps1 -InputPath "C:\Musica" -Preset per-auto -DryRun -Recurse
#
# Con esclusioni:
#   .\normalizzaV2_beta.ps1 -InputPath "C:\Musica" -Preset per-auto -ExcludeList "escludi.txt"

[CmdletBinding()]
param(
    [string]$InputPath,
    [string]$OutputPath,
    [ValidateSet("per-auto", "standard", "dinamico", "podcast", "custom")]
    [string]$Preset = "per-auto",
    [double]$TargetLUFS = -16.0,
    [string]$Bitrate = "320k",
    [switch]$Interactive,
    [switch]$Setup,
    [switch]$SkipSetupCheck,
    [string]$ToolsPath,

    # v2.0.0 - Dry-run, ricorsivita, esclusioni
    [switch]$DryRun,
    [switch]$Recurse,
    [string]$ExcludeList
)

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# ============================================
# COSTANTI VERSIONE
# ============================================

$ScriptVersion = "2.0.0"

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (-not $ToolsPath) { $ToolsPath = Join-Path $ScriptRoot "tools" }
$FfmpegDir  = Join-Path $ToolsPath "ffmpeg"
$FfmpegBin  = Join-Path $FfmpegDir "bin"
$FfmpegExe  = Join-Path $FfmpegBin "ffmpeg.exe"
$FfprobeExe = Join-Path $FfmpegBin "ffprobe.exe"
$FfmpegUrl  = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"

# ============================================
# LOGGING SU FILE (sempre attivo)
# ============================================

$script:LogFile = $null

function Start-Log {
    param([string]$Folder)

    if (-not (Test-Path $Folder)) {
        New-Item -ItemType Directory -Path $Folder -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:LogFile = Join-Path $Folder "normalizzazione_$timestamp.log"

    @(
        "============================================================",
        " LOG NORMALIZZAZIONE MP3 - EBU R128",
        " Versione script: $ScriptVersion",
        "============================================================",
        "Data inizio:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Input:        $InputPath",
        "Output:       $Folder",
        "Ricorsivo:    $Recurse",
        "Target LUFS:  $TargetLUFS",
        "Bitrate:      $Bitrate",
        "============================================================",
        ""
    ) | Set-Content -Path $script:LogFile -Encoding UTF8
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","OK","WARN","ERROR")][string]$Level = "INFO"
    )
    if (-not $script:LogFile) { return }
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
}

function Stop-Log {
    param(
        [int]$Total = 0,
        [int]$Success = 0,
        [int]$Failed = 0,
        [int]$Excluded = 0,
        [double]$Minutes = 0,
        [array]$FailedFiles = @()
    )
    if (-not $script:LogFile) { return }

    $footer = @(
        "",
        "============================================================",
        " RIEPILOGO FINALE",
        "============================================================",
        "Data fine:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Totale file:  $Total",
        "Successo:     $Success",
        "Falliti:      $Failed",
        "Esclusi:      $Excluded",
        "Tempo totale: $([math]::Round($Minutes, 2)) min",
        ""
    )

    if ($Failed -gt 0) {
        $footer += "--- FILE FALLITI ---"
        foreach ($f in $FailedFiles) {
            $footer += "  * $($f.Name)"
        }
        $footer += ""
    }

    $footer += "============================================================"
    $footer | Add-Content -Path $script:LogFile -Encoding UTF8
}

# ============================================
# FUNZIONI DI UTILITA
# ============================================

function Write-Step {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor $Color
    Write-Host "  $Message" -ForegroundColor $Color
    Write-Host ("=" * 60) -ForegroundColor $Color
}
function Write-Success  { param([string]$Message) Write-Host "  [OK] $Message" -ForegroundColor Green }
function Write-ErrorMsg { param([string]$Message) Write-Host "  [X] $Message"  -ForegroundColor Red }
function Write-Info     { param([string]$Message) Write-Host "  [i] $Message"  -ForegroundColor Yellow }
function Write-Warning  { param([string]$Message) Write-Host "  [!] $Message"  -ForegroundColor Magenta }

function Test-CommandAvailable {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-LocalFfmpeg {
    if ((Test-Path $FfmpegExe) -and (Test-Path $FfprobeExe)) {
        return @{ Ffmpeg = $FfmpegExe; Ffprobe = $FfprobeExe }
    }
    return $null
}

function Install-FfmpegLocal {
    param([string]$Url = $FfmpegUrl, [string]$Destination = $FfmpegDir)

    Write-Info "Download FFmpeg da: $Url"
    Write-Info "Destinazione: $Destination"
    Write-Host ""

    if (-not (Test-Path $ToolsPath)) {
        New-Item -ItemType Directory -Path $ToolsPath -Force | Out-Null
    }

    $zipPath = Join-Path $env:TEMP "ffmpeg_$(Get-Random).zip"

    try {
        $ProgressPreference = "SilentlyContinue"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        Write-Host "  Download in corso..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $Url -OutFile $zipPath -UseBasicParsing

        if (-not (Test-Path $zipPath)) { throw "Download fallito" }

        $sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
        Write-Success "Scaricati $sizeMB MB"

        $tempExtract = Join-Path $env:TEMP "ffmpeg_extract_$(Get-Random)"
        Write-Host "  Estrazione (puo richiedere 30-60s)..." -ForegroundColor Yellow
        Expand-Archive -Path $zipPath -DestinationPath $tempExtract -Force

        $extractedRoot = Get-ChildItem -Path $tempExtract -Directory | Select-Object -First 1
        if (-not $extractedRoot) { throw "Struttura archivio non riconosciuta" }

        $extractedBin = Join-Path $extractedRoot.FullName "bin"
        if (-not (Test-Path $extractedBin)) { throw "Cartella bin non trovata" }

        if (-not (Test-Path $FfmpegBin)) {
            New-Item -ItemType Directory -Path $FfmpegBin -Force | Out-Null
        }

        Copy-Item (Join-Path $extractedBin "ffmpeg.exe")  $FfmpegBin -Force
        Copy-Item (Join-Path $extractedBin "ffprobe.exe") $FfmpegBin -Force

        $licenseFile = Join-Path $extractedRoot.FullName "LICENSE"
        if (Test-Path $licenseFile) {
            Copy-Item $licenseFile (Join-Path $FfmpegDir "LICENSE.txt") -Force -ErrorAction SilentlyContinue
        }

        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

        Write-Success "FFmpeg installato in: $FfmpegBin"
        return $true
    } catch {
        Write-ErrorMsg "Installazione FFmpeg fallita: $($_.Exception.Message)"
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Initialize-FfmpegEnvironment {
    param([switch]$ForceSetup)

    if (-not $ForceSetup) {
        if ((Test-CommandAvailable "ffmpeg") -and (Test-CommandAvailable "ffprobe")) {
            $ver = (& ffmpeg -version 2>&1 | Select-Object -First 1)
            Write-Success "FFmpeg trovato nel PATH: $ver"
            return $true
        }
    }

    if (-not $ForceSetup) {
        $local = Get-LocalFfmpeg
        if ($local) {
            if ($env:PATH -notlike "*$FfmpegBin*") {
                $env:PATH = "$FfmpegBin;$env:PATH"
            }
            $ver = (& $FfmpegExe -version 2>&1 | Select-Object -First 1)
            Write-Success "FFmpeg locale trovato: $ver"
            return $true
        }
    }

    Write-Warning "FFmpeg non trovato (ne nel PATH ne in $FfmpegBin)"
    Write-Host ""
    Write-Host "  Opzioni:" -ForegroundColor White
    Write-Host "    1. Scarica automaticamente FFmpeg (~80 MB) in .\tools\ffmpeg" -ForegroundColor White
    Write-Host "    2. Salta (installerai FFmpeg manualmente)" -ForegroundColor White
    Write-Host ""

    do {
        $choice = Read-Host "Scegli (1-2, default 1)"
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }
        if ($choice -notmatch "^[1-2]$") { Write-Warning "1 o 2"; $choice = $null }
    } while (-not $choice)

    if ($choice -eq "1") {
        if (Install-FfmpegLocal) {
            $env:PATH = "$FfmpegBin;$env:PATH"
            return $true
        }
        return $false
    } else {
        Write-Info "Download saltato. Installa FFmpeg manualmente e riavvia lo script."
        Write-Info "Guida: https://ffmpeg.org/download.html"
        return $false
    }
}

$VolumePresets = @{
    "podcast"  = @{ LUFS = -16.0; Description = "Podcast/Audiolibri (ALTO - per ambienti rumorosi)" }
    "per-auto" = @{ LUFS = -15.0; Description = "Per-auto (volume piu alto, ideale per Android Auto)" }
    "standard" = @{ LUFS = -14.0; Description = "Standard Spotify/YouTube" }
    "dinamico" = @{ LUFS = -18.0; Description = "Dinamico (preserva differenze tra brani soft e forti)" }
}

function Invoke-LoudnormAnalysis {
    param([string]$FilePath, [double]$TargetLUFS = -16.0)

    $tempLog = [System.IO.Path]::Combine($env:TEMP, "loudnorm_$(Get-Random).log")
    $cmdLine = "ffmpeg -i `"$FilePath`" -af `"loudnorm=I=$($TargetLUFS):TP=-1.5:LRA=11:print_format=json`" -f null NUL > `"$tempLog`" 2>&1"
    $null = & cmd.exe /c $cmdLine

    $output = Get-Content $tempLog -Raw -ErrorAction SilentlyContinue
    Remove-Item $tempLog -Force -ErrorAction SilentlyContinue

    if ([string]::IsNullOrWhiteSpace($output)) { throw "Output FFmpeg vuoto" }

    $jsonStart = $output.IndexOf("{")
    if ($jsonStart -lt 0) {
        $preview = $output.Substring(0, [Math]::Min(300, $output.Length))
        throw "JSON non trovato. Output: $preview"
    }

    $jsonEnd = $output.LastIndexOf("}")
    if ($jsonEnd -le $jsonStart) { throw "JSON incompleto" }

    $jsonStr = $output.Substring($jsonStart, $jsonEnd - $jsonStart + 1)
    return $jsonStr | ConvertFrom-Json
}

function Get-MP3Tags {
    param([string]$FilePath)
    try {
        $result = ffprobe -v quiet -print_format json -show_format "$FilePath" 2>&1 | ConvertFrom-Json
        $tags = @{}
        if ($result.format.tags) {
            $result.format.tags.PSObject.Properties | ForEach-Object { $tags[$_.Name] = $_.Value }
        }
        $hasCover = $false
        if ($result.streams) {
            $hasCover = ($result.streams | Where-Object { $_.codec_name -eq "mjpeg" -or $_.codec_name -eq "png" }).Count -gt 0
        }
        return @{
            HasTags  = ($tags.Count -gt 0)
            HasCover = $hasCover
            Title    = if ($tags.title) { $tags.title } else { "N/D" }
            Artist   = if ($tags.artist) { $tags.artist } else { "N/D" }
        }
    } catch {
        return @{ HasTags = $false; HasCover = $false; Title = "N/D"; Artist = "N/D" }
    }
}

# ============================================
# v2.0.0 - FUNZIONI DRY-RUN
# ============================================

function Get-Mp3Duration {
    param([string]$FilePath)
    try {
        $duration = & ffprobe -v error -show_entries format=duration -of "default=noprint_wrappers=1:nokey=1" "$FilePath" 2>&1
        if ($duration -and $duration -match "^\d+\.?\d*$") {
            return [double]$duration
        }
        return $null
    } catch {
        return $null
    }
}

function Get-FileRiskLevel {
    param(
        [string]$FileName,
        [double]$DurationSeconds,
        [long]$FileSizeBytes
    )

    $nameLower = $FileName.ToLower()
    $minutes = $DurationSeconds / 60

    $risk = "Basso"
    $reasons = @()
    $bitrateKbps = 0

    # Calcola bitrate stimato (size * 8 / durata / 1000)
    if ($DurationSeconds -gt 0) {
        $bitrateKbps = [math]::Round(($FileSizeBytes * 8) / $DurationSeconds / 1000, 0)
    }

    # CHECK BITRATE ANOMALO (priorita' alta)
    if ($bitrateKbps -gt 400) {
        $risk = "ALTO"
        $reasons += "bitrate anomalo ($bitrateKbps kbps) - possibile file corrotto o mal codificato"
    } elseif ($bitrateKbps -gt 350) {
        if ($risk -eq "Basso") { $risk = "Medio" }
        $reasons += "bitrate alto ($bitrateKbps kbps)"
    }

    # Euristica basata su durata
    if ($minutes -gt 8) {
        $risk = "ALTO"
        $reasons += "durata > 8 min ($([math]::Round($minutes, 1)) min)"
    } elseif ($minutes -gt 6) {
        if ($risk -eq "Basso") { $risk = "Medio" }
        $reasons += "durata 6-8 min ($([math]::Round($minutes, 1)) min)"
    }

    # Euristica basata su nome file
    $livePatterns = @("live at", "live from", "(live)", "[live]", "- live", "_live")
    foreach ($pattern in $livePatterns) {
        if ($nameLower -match [regex]::Escape($pattern)) {
            if ($risk -eq "Basso") { $risk = "Medio" }
            $reasons += "nome contiene '$pattern'"
            break
        }
    }

    $otherKeywords = @("unplugged", "acoustic")
    foreach ($kw in $otherKeywords) {
        if ($nameLower -match $kw) {
            if ($risk -eq "Basso") { $risk = "Medio" }
            $reasons += "nome contiene '$kw'"
            break
        }
    }

    return @{
        Level        = $risk
        Reasons      = if ($reasons.Count -gt 0) { $reasons -join "; " } else { "nessuno" }
        BitrateKbps  = $bitrateKbps
        BitrateAlert = ($bitrateKbps -gt 400)
    }
}

function Format-Duration {
    param([double]$Seconds)
    if (-not $Seconds -or $Seconds -le 0) { return "N/D" }
    $ts = [TimeSpan]::FromSeconds($Seconds)
    return "{0}m {1:00}s" -f [int][math]::Floor($ts.TotalMinutes), $ts.Seconds
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -lt 1KB) { return "$Bytes B" }
    if ($Bytes -lt 1MB) { return "$([math]::Round($Bytes/1KB, 1)) KB" }
    if ($Bytes -lt 1GB) { return "$([math]::Round($Bytes/1MB, 1)) MB" }
    return "$([math]::Round($Bytes/1GB, 2)) GB"
}

# ============================================
# v2.0.0 - GESTIONE ESCLUSIONI
# ============================================

function Test-Excluded {
    param(
        [string]$FilePath,
        [string[]]$ExcludePatterns
    )

    if (-not $ExcludePatterns -or $ExcludePatterns.Count -eq 0) {
        return $false
    }

    $fileFullPath = $FilePath.ToLower()
    $fileName = (Split-Path $FilePath -Leaf).ToLower()

    foreach ($pattern in $ExcludePatterns) {
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        $p = $pattern.Trim().ToLower()

        if ($fileName -eq $p) { return $true }
        if ($fileFullPath -eq $p) { return $true }
        if ($fileFullPath -like "*$p*") { return $true }
    }

    return $false
}

function Load-ExcludeList {
    param([string]$Path)

    if (-not $Path -or -not (Test-Path $Path)) {
        return @()
    }

    $lines = Get-Content $Path -ErrorAction SilentlyContinue |
             Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith("#") }

    return @($lines | ForEach-Object { $_.Trim() })
}

function Start-DryRun {
    param(
        [string]$InputFolder,
        [string]$OutputFolder,
        [double]$TargetLUFS,
        [string]$Bitrate,
        [switch]$Recurse,
        [string[]]$ExcludePatterns = @()
    )

    Clear-Host
    Write-Host "+==========================================================+" -ForegroundColor Cyan
    Write-Host "|         DRY-RUN - ANALISI NORMALIZZAZIONE MP3            |" -ForegroundColor Cyan
    Write-Host "|                 (nessuna modifica effettuata)            |" -ForegroundColor Cyan
    Write-Host "+==========================================================+" -ForegroundColor Cyan
    Write-Host ""

    Write-Info "Ricerca file MP3 in: $InputFolder"
    if ($Recurse) {
        Write-Info "Modalita: RICORSIVA (incluse sottocartelle)"
        $mp3Files = @(Get-ChildItem -LiteralPath $InputFolder -Filter "*.mp3" -File -Recurse -ErrorAction SilentlyContinue)
    } else {
        Write-Info "Modalita: SOLO cartella principale (usa -Recurse per sottocartelle)"
        $mp3Files = @(Get-ChildItem -LiteralPath $InputFolder -Filter "*.mp3" -File -ErrorAction SilentlyContinue)
    }

    if ($ExcludePatterns.Count -gt 0) {
        Write-Info "Esclusioni attive: $($ExcludePatterns.Count) pattern"
    }

    $total = $mp3Files.Count
    if ($total -eq 0) {
        Write-ErrorMsg "Nessun MP3 trovato!"
        return
    }

    Write-Success "Trovati $total file MP3"
    Write-Host ""

    Write-Host "Analisi in corso (lettura durata e metadati)..." -ForegroundColor Yellow
    $analysis = New-Object System.Collections.ArrayList
    $excludedCount = 0
    $current = 0

    foreach ($file in $mp3Files) {
        $current++
        $percent = [math]::Round(($current / $total) * 100, 1)
        Write-Progress -Activity "Analisi dry-run..." -Status "[$current/$total] $percent% - $($file.Name)" -PercentComplete $percent

        if ($ExcludePatterns.Count -gt 0 -and (Test-Excluded -FilePath $file.FullName -ExcludePatterns $ExcludePatterns)) {
            $excludedCount++
            continue
        }

        $duration = Get-Mp3Duration -FilePath $file.FullName
        $durationSafe = if ($duration) { $duration } else { 0 }
        $risk = Get-FileRiskLevel -FileName $file.Name -DurationSeconds $durationSafe -FileSizeBytes $file.Length

        $estimatedSec = [math]::Round(($durationSafe / 11) + 2, 1)

        [void]$analysis.Add(@{
            File         = $file
            Duration     = $durationSafe
            Risk         = $risk.Level
            RiskReasons  = $risk.Reasons
            EstimatedSec = $estimatedSec
            BitrateKbps  = $risk.BitrateKbps
            BitrateAlert = $risk.BitrateAlert
        })
    }

    Write-Progress -Activity "Analisi dry-run..." -Completed

    $analyzedCount = $analysis.Count
    $totalSize = ($analysis | ForEach-Object { $_.File.Length } | Measure-Object -Sum).Sum
    $totalDuration = ($analysis | Measure-Object -Property Duration -Sum).Sum
    $totalEstimated = ($analysis | Measure-Object -Property EstimatedSec -Sum).Sum

    $bitrateBps = switch ($Bitrate) {
        "320k" { 320000 }
        "256k" { 256000 }
        "192k" { 192000 }
        "128k" { 128000 }
        default { 320000 }
    }
    $estimatedOutputBytes = ($totalDuration * $bitrateBps) / 8

    $driveLetter = (Get-Item $OutputFolder -ErrorAction SilentlyContinue).PSDrive.Name
    if (-not $driveLetter) {
        $driveLetter = (Get-Item $InputFolder).PSDrive.Name
    }
    $driveInfo = Get-PSDrive $driveLetter -ErrorAction SilentlyContinue
    $freeBytes = if ($driveInfo) { $driveInfo.Free } else { 0 }

    if (-not (Test-Path $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $reportFile = Join-Path $OutputFolder "dryrun_$timestamp.txt"

    $report = @()
    $report += "============================================================"
    $report += " DRY-RUN - NORMALIZZAZIONE MP3 - EBU R128"
    $report += " Versione script: $ScriptVersion"
    $report += "============================================================"
    $report += "Data analisi:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $report += "Cartella input:  $InputFolder"
    $report += "Cartella output: $OutputFolder"
    $report += "Ricorsivo:       $Recurse"
    $report += "Target LUFS:     $TargetLUFS"
    $report += "Bitrate output:  $Bitrate"
    if ($excludedCount -gt 0) {
        $report += "File esclusi:    $excludedCount"
    }
    $report += "============================================================"
    $report += ""
    $report += "--- RIEPILOGO ---"
    $report += "File MP3 trovati:            $total"
    if ($excludedCount -gt 0) {
        $report += "File esclusi:                $excludedCount"
        $report += "File da processare:          $analyzedCount"
    }
    $report += "Dimensione totale input:     $(Format-Size $totalSize)"
    $report += "Durata totale audio:         $(Format-Duration $totalDuration)"
    $report += "Tempo stimato elaborazione:  ~$(Format-Duration $totalEstimated)"
    $report += "Spazio stimato output:       ~$(Format-Size $estimatedOutputBytes)"
    $report += "Spazio libero disco:         $(Format-Size $freeBytes)"

    if ($freeBytes -gt 0 -and $estimatedOutputBytes -gt $freeBytes) {
        $report += "*** ATTENZIONE: spazio libero INSUFFICIENTE ***"
    } else {
        $report += "Spazio disco:                sufficiente"
    }
    $report += ""

    $riskCounts = $analysis | Group-Object { $_.Risk } | Sort-Object Name
    $report += "--- DISTRIBUZIONE RISCHIO ---"
    foreach ($rc in $riskCounts) {
        $report += "Rischio $($rc.Name): $($rc.Count) file"
    }
    $report += ""

    $report += "--- DETTAGLIO FILE ---"
    $report += "Formato: [N] Nome | Durata | Size | Bitrate | Rischio | Stima"
    $report += ""

    $i = 0
    foreach ($item in $analysis) {
        $i++
        $num = "{0,3}" -f $i
        $dur = Format-Duration $item.Duration
        $size = Format-Size $item.File.Length
        $est = "$($item.EstimatedSec)s"
        $risk = $item.Risk
        $bitrate = "$($item.BitrateKbps) kbps"
        $report += "[$num] $($item.File.Name)"
        $report += "      Durata: $dur | Size: $size | Bitrate: $bitrate | Rischio: $risk | Stima: $est"
        if ($item.Risk -ne "Basso" -and $item.RiskReasons -ne "nessuno") {
            $report += "      Motivo: $($item.RiskReasons)"
        }
        $report += ""
    }

    $bitrateAnomalies = $analysis | Where-Object { $_.BitrateAlert -eq $true }
    if ($bitrateAnomalies.Count -gt 0) {
        $report += "============================================================"
        $report += " !!! FILE CON BITRATE ANOMALO (da riparare con EaseUS Fixo) !!!"
        $report += "============================================================"
        $report += "Questi file hanno un bitrate stimato > 400 kbps (impossibile per MP3)."
        $report += "Probabile header corrotto o file mal codificato."
        $report += ""
        foreach ($ba in $bitrateAnomalies) {
            $dur = Format-Duration $ba.Duration
            $size = Format-Size $ba.File.Length
            $report += "  * $($ba.File.Name)"
            $report += "    Durata: $dur | Size: $size | Bitrate: $($ba.BitrateKbps) kbps"
        }
        $report += ""
    }

    $highRisk = $analysis | Where-Object { $_.Risk -eq "ALTO" -and $_.BitrateAlert -ne $true }
    if ($highRisk.Count -gt 0) {
        $report += "============================================================"
        $report += " FILE AD ALTO RISCHIO (da verificare a orecchio)"
        $report += "============================================================"
        foreach ($hr in $highRisk) {
            $report += "  * $($hr.File.Name)"
            $report += "    $($hr.RiskReasons)"
        }
        $report += ""
    }

    if ($ExcludeList -and (Test-Path $ExcludeList)) {
        $report += "============================================================"
        $report += " ESCLUSIONI ATTIVE"
        $report += "============================================================"
        $report += "File esclusioni: $ExcludeList"
        $report += "Pattern caricati: $($ExcludePatterns.Count)"
        $report += "File esclusi in questa analisi: $excludedCount"
        $report += ""
    }

    $report += "============================================================"
    $report += " FINE REPORT - NESSUNA MODIFICA EFFETTUATA"
    $report += "============================================================"

    $report | Set-Content -Path $reportFile -Encoding UTF8

    Write-Host ""
    Write-Host "+==========================================+" -ForegroundColor Green
    Write-Host "|         DRY-RUN COMPLETATO               |" -ForegroundColor Green
    Write-Host "+==========================================+" -ForegroundColor Green
    Write-Host "| File analizzati:  $analyzedCount" -ForegroundColor White
    if ($excludedCount -gt 0) {
        Write-Host "| File esclusi:     $excludedCount" -ForegroundColor DarkGray
    }
    Write-Host "| Durata totale:    $(Format-Duration $totalDuration)" -ForegroundColor White
    Write-Host "| Tempo stimato:    ~$(Format-Duration $totalEstimated)" -ForegroundColor White
    Write-Host "| Spazio stimato:   ~$(Format-Size $estimatedOutputBytes)" -ForegroundColor White
    Write-Host "| Spazio libero:    $(Format-Size $freeBytes)" -ForegroundColor White
    Write-Host "+==========================================+" -ForegroundColor Green
    Write-Host ""
    Write-Host "Distribuzione rischio:" -ForegroundColor Cyan
    foreach ($rc in $riskCounts) {
        $color = switch ($rc.Name) {
            "ALTO"  { "Red" }
            "Medio" { "Yellow" }
            default { "Green" }
        }
        Write-Host "  Rischio $($rc.Name): $($rc.Count) file" -ForegroundColor $color
    }
    Write-Host ""
    Write-Host "Report completo: $reportFile" -ForegroundColor Magenta
    Write-Host "NESSUNA MODIFICA EFFETTUATA." -ForegroundColor Green
}
# ============================================
# NORMALIZZAZIONE SINGOLO FILE
# ============================================

function Normalize-SingleMP3 {
    param(
        [string]$InputFile,
        [string]$OutputFile,
        [double]$TargetLUFS = -16.0,
        [string]$Bitrate = "320k"
    )

    $tempFile = [System.IO.Path]::Combine($env:TEMP, "norm_$(Get-Random).mp3")

    try {
        $info = Invoke-LoudnormAnalysis -FilePath $InputFile -TargetLUFS $TargetLUFS

        $inputI       = $info.input_i
        $inputTP      = $info.input_tp
        $inputLRA     = $info.input_lra
        $inputThresh  = $info.input_thresh
        $targetOffset = $info.target_offset

        if ($inputI -eq "-inf" -or $inputI -eq "nan" -or [string]::IsNullOrWhiteSpace($inputI)) {
            throw "File silenzioso o misura non valida"
        }

        $normalizeFilter = "loudnorm=I=$($TargetLUFS):TP=-1.5:LRA=11:measured_I=$($inputI):measured_TP=$($inputTP):measured_LRA=$($inputLRA):measured_thresh=$($inputThresh):offset=$($targetOffset):linear=false:print_format=summary"

        $normalizeArgs = @(
            "-i", $InputFile,
            "-af", $normalizeFilter,
            "-c:a", "libmp3lame",
            "-ar", "44100",
            "-b:a", $Bitrate,
            "-y", $tempFile
        )
        $null = & ffmpeg @normalizeArgs 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Normalizzazione fallita" }

        $mergeArgs = @(
            "-i", $tempFile,
            "-i", $InputFile,
            "-map", "0:a",
            "-map", "1:v?",
            "-map_metadata", "1",
            "-c:a", "copy",
            "-c:v", "copy",
            "-disposition:v", "attached_pic",
            "-id3v2_version", "3",
            "-write_id3v1", "1",
            "-y", $OutputFile
        )
        $null = & ffmpeg @mergeArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Merge metadati fallito - copia solo audio"
            Copy-Item $tempFile $OutputFile -Force
        }

        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        Write-Host " [X] $($_.Exception.Message)" -ForegroundColor Red
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        return $false
    }
}

# ============================================
# NORMALIZZAZIONE BATCH
# ============================================

function Normalize-MP3Batch {
    param(
        [string]$InputFolder,
        [string]$OutputFolder,
        [double]$TargetLUFS = -16.0,
        [string]$Bitrate = "320k",
        [switch]$Recurse,
        [string[]]$ExcludePatterns = @()
    )

    if ($Recurse) {
        $mp3Files = @(Get-ChildItem -LiteralPath $InputFolder -Filter "*.mp3" -File -Recurse -ErrorAction SilentlyContinue)
    } else {
        $mp3Files = @(Get-ChildItem -LiteralPath $InputFolder -Filter "*.mp3" -File -ErrorAction SilentlyContinue)
    }

    $total = $mp3Files.Count
    if ($total -eq 0) { Write-ErrorMsg "Nessun MP3 trovato!"; return }

    if (-not (Test-Path $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }

    Start-Log -Folder $OutputFolder
    Write-Log "Avvio normalizzazione: $total file, target $TargetLUFS LUFS, bitrate $Bitrate, ricorsivo=$Recurse, esclusioni=$($ExcludePatterns.Count)" "INFO"

    Write-Step "AVVIO NORMALIZZAZIONE" "Green"
    Write-Info "File: $total | Target: $TargetLUFS LUFS | Bitrate: $Bitrate | Ricorsivo: $Recurse"
    if ($ExcludePatterns.Count -gt 0) {
        Write-Info "Esclusioni: $($ExcludePatterns.Count) pattern"
    }
    Write-Info "Log: $script:LogFile"
    Write-Host ""

    $startTime = Get-Date
    $success = 0
    $failed = 0
    $excludedCount = 0
    $current = 0
    $totalOriginalSize = 0
    $totalOutputSize = 0
    $failedFiles = New-Object System.Collections.ArrayList

    foreach ($file in $mp3Files) {
        $current++

        if ($ExcludePatterns.Count -gt 0 -and (Test-Excluded -FilePath $file.FullName -ExcludePatterns $ExcludePatterns)) {
            Write-Log "$($file.Name) - ESCLUSO (match pattern)" "WARN"
            Write-Host "[$current/$total] $($file.Name) [ESCLUSO]" -ForegroundColor DarkGray
            $excludedCount++
            continue
        }

        $percent = [math]::Round(($current / $total) * 100, 1)

        if ($Recurse) {
            $relativePath = $file.FullName.Substring($InputFolder.Length).TrimStart("\")
            $outputFile = Join-Path $OutputFolder $relativePath
            $outputDir = Split-Path $outputFile -Parent
            if (-not (Test-Path $outputDir)) {
                New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
            }
        } else {
            $outputFile = Join-Path $OutputFolder $file.Name
        }

        Write-Progress -Activity "Normalizzazione..." -Status "[$current/$total] $percent% - $($file.Name)" -PercentComplete $percent

        $tags = Get-MP3Tags -FilePath $file.FullName
        $tagInfo = ""
        if ($tags.HasTags) {
            $tagInfo = " | $($tags.Artist) - $($tags.Title)"
            if ($tags.HasCover) { $tagInfo += " [img]" }
        }

        Write-Host "[$current/$total] $($file.Name)$tagInfo" -ForegroundColor Gray -NoNewline
        $fileStart = Get-Date

        if (Normalize-SingleMP3 -InputFile $file.FullName -OutputFile $outputFile -TargetLUFS $TargetLUFS -Bitrate $Bitrate) {
            $elapsed = ($(Get-Date) - $fileStart).TotalSeconds
            Write-Host " [OK] ($([math]::Round($elapsed, 1))s)" -ForegroundColor Green
            Write-Log "$($file.Name) - OK ($([math]::Round($elapsed, 1))s)" "OK"
            $totalOriginalSize += $file.Length
            if (Test-Path $outputFile) {
                $totalOutputSize += (Get-Item $outputFile).Length
            }
            $success++
        } else {
            Write-Host " [X] FALLITO" -ForegroundColor Red
            Write-Log "$($file.Name) - FALLITO" "ERROR"
            [void]$failedFiles.Add(@{ Name = $file.Name })
            $failed++
        }
    }

    Write-Progress -Activity "Normalizzazione..." -Completed

    $totalTime = ($(Get-Date) - $startTime).TotalMinutes

    Write-Host ""
    Write-Host "+==========================================+" -ForegroundColor Green
    Write-Host "|     NORMALIZZAZIONE COMPLETATA           |" -ForegroundColor Green
    Write-Host "+==========================================+" -ForegroundColor Green
    Write-Host "| Totale:   $total" -ForegroundColor White
    if ($excludedCount -gt 0) { Write-Host "| Esclusi:  $excludedCount" -ForegroundColor DarkGray }
    Write-Host "| Successo: $success" -ForegroundColor Green
    if ($failed -gt 0) { Write-Host "| Falliti:  $failed" -ForegroundColor Red }
    Write-Host "| Tempo:    $([math]::Round($totalTime, 1)) min" -ForegroundColor White
    if ($totalOriginalSize -gt 0 -and $totalOutputSize -gt 0) {
        Write-Host "| Orig:     $([math]::Round($totalOriginalSize/1MB, 1)) MB" -ForegroundColor White
        Write-Host "| Output:   $([math]::Round($totalOutputSize/1MB, 1)) MB" -ForegroundColor White
    }
    Write-Host "+==========================================+" -ForegroundColor Green
    Write-Host ""

    if ($failed -gt 0) {
        Write-Host "--- FILE FALLITI ---" -ForegroundColor Red
        foreach ($f in $failedFiles) {
            Write-Host "  * $($f.Name)" -ForegroundColor Red
        }
        Write-Host ""
    }

    Write-Host "File normalizzati in: $OutputFolder" -ForegroundColor Magenta

    Stop-Log -Total $total -Success $success -Failed $failed -Excluded $excludedCount -Minutes $totalTime -FailedFiles $failedFiles
    Write-Host "Log salvato in: $script:LogFile" -ForegroundColor Magenta
}

function Start-SetupMode {
    Clear-Host
    Write-Host "+==========================================================+" -ForegroundColor Cyan
    Write-Host "|           SETUP AMBIENTE - NORMALIZZATORE MP3            |" -ForegroundColor Cyan
    Write-Host "+==========================================================+" -ForegroundColor Cyan
    Write-Host ""

    Write-Step "Verifica FFmpeg" "Cyan"
    $ok = Initialize-FfmpegEnvironment -ForceSetup

    if ($ok) {
        Write-Host ""
        Write-Success "Ambiente pronto!"
        Write-Info "Cartella tools: $ToolsPath"
        Write-Info "Puoi ora lanciare lo script senza parametri."
    } else {
        Write-Host ""
        Write-ErrorMsg "Setup non completato."
    }

    Write-Host ""
    Write-Host "Premi un tasto per uscire..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Start-InteractiveMode {
    Clear-Host
    Write-Host "+==========================================================+" -ForegroundColor Magenta
    Write-Host "|        NORMALIZZATORE VOLUME MP3 - EBU R128              |" -ForegroundColor Magenta
    Write-Host "|                  Versione $ScriptVersion                        |" -ForegroundColor Magenta
    Write-Host "|      PRESERVA TAG ID3, COPERTINE E METADATI              |" -ForegroundColor Magenta
    Write-Host "+==========================================================+" -ForegroundColor Magenta
    Write-Host ""

    Write-Step "STEP 1: Verifica ambiente FFmpeg" "Cyan"
    if (-not (Initialize-FfmpegEnvironment)) {
        Write-ErrorMsg "Impossibile procedere senza FFmpeg."
        Write-Host ""
        Write-Host "Premi un tasto per uscire..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }

    Write-Step "STEP 2: Cartella MP3" "Cyan"
    Add-Type -AssemblyName System.Windows.Forms
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Seleziona la cartella con i tuoi MP3"
    if ($folderBrowser.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-ErrorMsg "Nessuna cartella selezionata."
        return
    }
    $InputPath = $folderBrowser.SelectedPath
    Write-Success "Cartella: $InputPath"

    Write-Step "STEP 2b: Modalita ricorsiva?" "Cyan"
    Write-Host "  Includere anche le sottocartelle?" -ForegroundColor White
    Write-Host "  1. No (solo cartella principale) - default"
    Write-Host "  2. Si (incluse tutte le sottocartelle)"
    Write-Host ""
    do {
        $recChoice = Read-Host "Scegli (1-2, default 1)"
        if ([string]::IsNullOrWhiteSpace($recChoice)) { $recChoice = "1" }
        if ($recChoice -notmatch "^[1-2]$") { Write-Warning "1 o 2"; $recChoice = $null }
    } while (-not $recChoice)

    $useRecurse = $recChoice -eq "2"
    if ($useRecurse) {
        $Recurse = $true
        Write-Success "Modalita: RICORSIVA"
    } else {
        $Recurse = $false
        Write-Success "Modalita: solo cartella principale"
    }

    if ($Recurse) {
        $mp3Files = @(Get-ChildItem -LiteralPath $InputPath -Filter "*.mp3" -File -Recurse -ErrorAction SilentlyContinue)
    } else {
        $mp3Files = @(Get-ChildItem -LiteralPath $InputPath -Filter "*.mp3" -File -ErrorAction SilentlyContinue)
    }

    if ($mp3Files.Count -eq 0) {
        Write-ErrorMsg "Nessun MP3 trovato!"
        Write-Host ""
        Write-Host "Premi un tasto per uscire..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }
    Write-Success "Trovati $($mp3Files.Count) file MP3"

    Write-Step "STEP 3: Profilo volume" "Cyan"
    $i = 1
    foreach ($key in $VolumePresets.Keys) {
        Write-Host "  $i. $key - $($VolumePresets[$key].Description)" -ForegroundColor White
        $i++
    }
    Write-Host "  $i. Custom" -ForegroundColor White
    Write-Host ""

    do {
        $profileChoice = Read-Host "Scegli (1-$i, default 2)"
        if ([string]::IsNullOrWhiteSpace($profileChoice)) { $profileChoice = "2" }
        if ($profileChoice -notmatch "^\d+$" -or [int]$profileChoice -lt 1 -or [int]$profileChoice -gt $i) {
            Write-Warning "Numero non valido"; $profileChoice = $null
        }
    } while (-not $profileChoice)

    $keys = @($VolumePresets.Keys)
    if ([int]$profileChoice -le $keys.Count) {
        $chosenKey = $keys[[int]$profileChoice - 1]
        $TargetLUFS = $VolumePresets[$chosenKey].LUFS
        $descrizioneProfilo = $VolumePresets[$chosenKey].Description
    } else {
        do {
            $customLUFS = Read-Host "Inserisci target LUFS (da -10 a -30, default -16)"
            if ([string]::IsNullOrWhiteSpace($customLUFS)) { $customLUFS = "-16" }
            try {
                $TargetLUFS = [double]$customLUFS
                if ($TargetLUFS -lt -30 -or $TargetLUFS -gt -10) {
                    Write-Warning "Fuori range (-10 a -30)"; $TargetLUFS = $null
                }
            } catch { Write-Warning "Numero non valido"; $TargetLUFS = $null }
        } while (-not $TargetLUFS)
        $descrizioneProfilo = "Custom ($TargetLUFS LUFS)"
    }
    Write-Success "Profilo: $descrizioneProfilo"

    Write-Step "STEP 4: Bitrate" "Cyan"
    Write-Host "  1. 320 kbps - Massima qualita (consigliato)"
    Write-Host "  2. 256 kbps - Alta qualita"
    Write-Host "  3. 192 kbps - Buona qualita (per auto)"
    Write-Host "  4. 128 kbps - File piccoli"
    Write-Host ""
    do {
        $bitrateChoice = Read-Host "Scegli (1-4, default 1)"
        if ([string]::IsNullOrWhiteSpace($bitrateChoice)) { $bitrateChoice = "1" }
        if ($bitrateChoice -notmatch "^[1-4]$") { Write-Warning "1-4"; $bitrateChoice = $null }
    } while (-not $bitrateChoice)
    switch ($bitrateChoice) {
        "1" { $Bitrate = "320k" }
        "2" { $Bitrate = "256k" }
        "3" { $Bitrate = "192k" }
        "4" { $Bitrate = "128k" }
    }
    Write-Success "Bitrate: $Bitrate"

    Write-Step "STEP 5: Cartella output" "Cyan"
    Write-Host "  1. Sottocartella Normalizzati (preserva originali - consigliato)"
    Write-Host "  2. Sostituisci originali (SOVRASCRIVE - pericoloso!)"
    Write-Host ""
    do {
        $outputChoice = Read-Host "Scegli (1-2, default 1)"
        if ([string]::IsNullOrWhiteSpace($outputChoice)) { $outputChoice = "1" }
        if ($outputChoice -notmatch "^[1-2]$") { Write-Warning "1-2"; $outputChoice = $null }
    } while (-not $outputChoice)

    if ($outputChoice -eq "1") {
        $OutputPath = Join-Path $InputPath "Normalizzati"
    } else {
        $OutputPath = $InputPath
        Write-Warning "Originali verranno SOVRASCRITTI!"
    }
    Write-Success "Output: $OutputPath"

    Write-Step "STEP 6: Dry-run o normalizzazione?" "Cyan"
    Write-Host "  1. NORMALIZZA (elabora e scrive i file) - default"
    Write-Host "  2. DRY-RUN (solo analisi e report, nessuna modifica)"
    Write-Host ""
    do {
        $modeChoice = Read-Host "Scegli (1-2, default 1)"
        if ([string]::IsNullOrWhiteSpace($modeChoice)) { $modeChoice = "1" }
        if ($modeChoice -notmatch "^[1-2]$") { Write-Warning "1-2"; $modeChoice = $null }
    } while (-not $modeChoice)

    $isDryRun = $modeChoice -eq "2"

    Write-Step "STEP 7: Conferma" "Yellow"
    Write-Host ""
    Write-Host "  +=======================================+" -ForegroundColor Cyan
    if ($isDryRun) {
        Write-Host "  |         RIEPILOGO DRY-RUN             |" -ForegroundColor Cyan
    } else {
        Write-Host "  |      RIEPILOGO NORMALIZZAZIONE        |" -ForegroundColor Cyan
    }
    Write-Host "  +=======================================+" -ForegroundColor Cyan
    Write-Host "  | File:       $($mp3Files.Count) MP3" -ForegroundColor White
    Write-Host "  | Ricorsivo:  $Recurse" -ForegroundColor White
    Write-Host "  | Target:     $TargetLUFS LUFS" -ForegroundColor White
    Write-Host "  | Profilo:    $descrizioneProfilo" -ForegroundColor White
    Write-Host "  | Bitrate:    $Bitrate" -ForegroundColor White
    Write-Host "  | Output:     $OutputPath" -ForegroundColor White
    Write-Host "  | Metadati:   TUTTI PRESERVATI" -ForegroundColor Green
    Write-Host "  | Log:        SEMPRE ATTIVO" -ForegroundColor Green
    if ($isDryRun) {
        Write-Host "  | Modalita:   DRY-RUN (nessuna modifica)" -ForegroundColor Yellow
    } else {
        Write-Host "  | Modalita:   NORMALIZZAZIONE" -ForegroundColor Green
    }
    Write-Host "  +=======================================+" -ForegroundColor Cyan
    Write-Host ""

    $confirm = Read-Host "Procedere? (S/N)"
    if ($confirm -ne "S" -and $confirm -ne "s") {
        Write-ErrorMsg "Annullato."
        return
    }

    if ($isDryRun) {
        Start-DryRun -InputFolder $InputPath -OutputFolder $OutputPath -TargetLUFS $TargetLUFS -Bitrate $Bitrate -Recurse:$Recurse
    } else {
        Normalize-MP3Batch -InputFolder $InputPath -OutputFolder $OutputPath -TargetLUFS $TargetLUFS -Bitrate $Bitrate -Recurse:$Recurse
    }

    $open = Read-Host "`nAprire cartella output? (S/N)"
    if ($open -eq "S" -or $open -eq "s") {
        Start-Process explorer.exe -ArgumentList $OutputPath
    }

    Write-Host ""
    Write-Host "Premi un tasto per uscire..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

## ============================================
# ESECUZIONE
# ============================================

# Risolvi il preset -> TargetLUFS (se non e' custom)
if ($Preset -ne "custom") {
    if ($VolumePresets.ContainsKey($Preset)) {
        $TargetLUFS = $VolumePresets[$Preset].LUFS
    }
}

if ($Setup) {
    Start-SetupMode
    return
}

if (-not $SkipSetupCheck) {
    if (-not (Initialize-FfmpegEnvironment)) {
        if ($InputPath) {
            Write-ErrorMsg "FFmpeg mancante. Esegui: .\normalizza.ps1 -Setup"
            exit 1
        }
    }
}

$excludePatterns = @()
if ($ExcludeList) {
    if (-not (Test-Path $ExcludeList)) {
        Write-Warning "File esclusioni non trovato: $ExcludeList (verra' ignorato)"
    } else {
        $excludePatterns = Load-ExcludeList -Path $ExcludeList
        Write-Info "Esclusioni caricate: $($excludePatterns.Count) pattern da '$ExcludeList'"
    }
}

if ($DryRun) {
    if (-not $InputPath) {
        Write-ErrorMsg "Dry-run richiede -InputPath."
        exit 1
    }
    if (-not $OutputPath) { $OutputPath = Join-Path $InputPath "Normalizzati" }
    Start-DryRun -InputFolder $InputPath -OutputFolder $OutputPath -TargetLUFS $TargetLUFS -Bitrate $Bitrate -Recurse:$Recurse -ExcludePatterns $excludePatterns
    return
}

if ($Interactive -or (-not $InputPath)) {
    Start-InteractiveMode
} elseif ($InputPath) {
    if (-not $OutputPath) { $OutputPath = Join-Path $InputPath "Normalizzati" }
    Normalize-MP3Batch -InputFolder $InputPath -OutputFolder $OutputPath -TargetLUFS $TargetLUFS -Bitrate $Bitrate -Recurse:$Recurse -ExcludePatterns $excludePatterns
}