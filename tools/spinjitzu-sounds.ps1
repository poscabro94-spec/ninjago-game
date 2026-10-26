# spinjitzu-sounds v1.0
# Pulls the audio out of the Spinjitzu videos and cuts each one into three .ogg clips for Roblox:
#   <Element> Start.ogg  wind-up, ends exactly where the loop begins
#   <Element> Loop.ogg   seamless loop (its end is crossfaded into its start)
#   <Element> End.ogg    the stopping sound
# Cut points come from spinjitzu-cuts.csv (seconds, blank = guess from where the sound starts/stops).
# The cut points actually used are written to "cuts used.txt" in the output folder.
#
# Needs ffmpeg + ffprobe on PATH:  winget install Gyan.FFmpeg   (then open a new PowerShell window)
#
#   powershell -ExecutionPolicy Bypass -File tools\spinjitzu-sounds.ps1             # cut all clips
#   powershell -ExecutionPolicy Bypass -File tools\spinjitzu-sounds.ps1 -FullOnly   # only dump each full soundtrack to listen to
#   powershell -ExecutionPolicy Bypass -File tools\spinjitzu-sounds.ps1 -Only Fire  # just one element

param(
	[string]$VideoDir = (Join-Path $env:USERPROFILE "Videos"),
	[string]$OutDir = (Join-Path $env:USERPROFILE "Downloads\Spinjitzu Sounds"),
	[string]$CutsFile = (Join-Path $PSScriptRoot "spinjitzu-cuts.csv"),
	[double]$LoopFade = 0.25,     # crossfade length (s) that hides the loop seam
	[double]$EndFade = 0.15,      # fade-out at the very end of the End clip
	[string]$Only = "",
	[switch]$FullOnly,
	[switch]$Stereo               # default is mono (Roblox positions 3D sounds better in mono)
)

$ErrorActionPreference = "Stop"
$inv = [Globalization.CultureInfo]::InvariantCulture   # always "1.5", never "1,5"
function Num([string]$s) { [double]::Parse($s.Trim(), $inv) }
function Str([double]$x) { $x.ToString("0.###", $inv) }

foreach ($tool in "ffmpeg", "ffprobe") {
	if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
		throw "$tool not found. Install it with:  winget install Gyan.FFmpeg   then open a new PowerShell window."
	}
}

$channels = if ($Stereo) { "2" } else { "1" }
$encode = @("-c:a", "libvorbis", "-q:a", "6", "-ac", $channels, "-ar", "44100")

function Invoke-FFmpeg([string[]]$ffArgs) {
	& ffmpeg -hide_banner -loglevel error -y @ffArgs
	if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed: ffmpeg $($ffArgs -join ' ')" }
}

function Get-Duration([string]$src) {
	$d = & ffprobe -v error -select_streams a:0 -show_entries format=duration -of csv=p=0 $src
	if ($LASTEXITCODE -ne 0 -or -not $d) { throw "Couldn't read $src (does it have an audio track?)" }
	Num "$d"
}

# first and last moment that isn't silence
function Get-SoundSpan([string]$src, [double]$dur) {
	$old = $ErrorActionPreference
	$ErrorActionPreference = "Continue"   # ffmpeg logs to stderr
	$log = & ffmpeg -hide_banner -nostats -i $src -map 0:a:0 -af "silencedetect=noise=-45dB:d=0.25" -f null - 2>&1 | ForEach-Object { "$_" }
	$ErrorActionPreference = $old
	$starts = @(); $ends = @()
	foreach ($line in $log) {
		if ($line -match "silence_start: (-?[\d.]+)") { $starts += Num $Matches[1] }
		if ($line -match "silence_end: ([\d.]+)") { $ends += Num $Matches[1] }
	}
	$first = 0.0; $last = $dur
	if ($starts.Count -gt 0 -and $starts[0] -le 0.05 -and $ends.Count -gt 0) { $first = $ends[0] }
	if ($starts.Count -gt $ends.Count) { $last = $starts[-1] }
	elseif ($ends.Count -gt 0 -and $ends[-1] -ge $dur - 0.1 -and $starts[-1] -gt $first) { $last = $starts[-1] }
	if ($last - $first -lt 1.0) { $first = 0.0; $last = $dur }   # mostly silent? use everything
	@($first, $last)
}

if (-not (Test-Path $CutsFile)) { throw "Cut list not found: $CutsFile" }
$rows = Import-Csv $CutsFile
if ($Only) { $rows = $rows | Where-Object { $_.Element -eq $Only } }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$report = @("Element   ClipStart  LoopStart  LoopEnd  ClipEnd   (seconds in the video)")

foreach ($row in $rows) {
	$name = $row.Element
	$src = Join-Path $VideoDir $row.Video
	if (-not (Test-Path $src)) { Write-Warning "$name`: $src not found, skipped"; continue }
	$dur = Get-Duration $src

	if ($FullOnly) {
		$full = Join-Path $OutDir "$name Full.ogg"
		Invoke-FFmpeg (@("-i", $src, "-map", "0:a:0", "-vn") + $encode + @($full))
		Write-Host ("{0,-10} {1}s -> {2}" -f $name, (Str $dur), $full)
		continue
	}

	# fill blanks: sound span, 20% (max 1s) wind-up and stop, loop in between
	$span = $null
	if (-not ($row.ClipStart -and $row.ClipEnd)) { $span = Get-SoundSpan $src $dur }
	$S = if ($row.ClipStart) { Num $row.ClipStart } else { $span[0] }
	$X = if ($row.ClipEnd) { Num $row.ClipEnd } else { $span[1] }
	$X = [Math]::Min($X, $dur)
	$edge = [Math]::Min(1.0, ($X - $S) * 0.2)
	$L = if ($row.LoopStart) { Num $row.LoopStart } else { $S + $edge }
	$E = if ($row.LoopEnd) { Num $row.LoopEnd } else { $X - $edge }
	$F = $LoopFade

	if (-not ($S -lt $L -and $L + 2 * $F -lt $E -and $E -lt $X)) {
		Write-Warning ("$name`: cut points must go ClipStart < LoopStart < LoopEnd < ClipEnd with at least {0}s of loop (got {1} / {2} / {3} / {4}), skipped" -f (Str (2 * $F)), (Str $S), (Str $L), (Str $E), (Str $X))
		continue
	}
	$fadeOutAt = [Math]::Max(0, $X - $E - $EndFade)

	# Start: ClipStart -> LoopStart+fade (the loop clip begins at LoopStart+fade)
	$startF = "[0:a:0]atrim=start=$(Str $S):end=$(Str ($L + $F)),asetpts=PTS-STARTPTS,afade=t=in:d=0.02[out]"
	# Loop: LoopStart+fade -> LoopEnd, with LoopStart -> LoopStart+fade crossfaded over its tail,
	# so the last sample leads straight back into the first
	# (reads the video twice: asplit + acrossfade silently gives an empty file)
	$loopF = "[0:a:0]atrim=start=$(Str ($L + $F)):end=$(Str $E),asetpts=PTS-STARTPTS[body];" +
		"[1:a:0]atrim=start=$(Str $L):end=$(Str ($L + $F)),asetpts=PTS-STARTPTS[head];" +
		"[body][head]acrossfade=d=$(Str $F):c1=qsin:c2=qsin[out]"
	# End: LoopEnd -> ClipEnd, short fade in (it starts mid-sound) and fade out
	$endF = "[0:a:0]atrim=start=$(Str $E):end=$(Str $X),asetpts=PTS-STARTPTS,afade=t=in:d=0.03,afade=t=out:st=$(Str $fadeOutAt):d=$(Str $EndFade)[out]"

	foreach ($clip in @(@("Start", $startF, 1), @("Loop", $loopF, 2), @("End", $endF, 1))) {
		$dst = Join-Path $OutDir "$name $($clip[0]).ogg"
		$inputs = @(); for ($i = 0; $i -lt $clip[2]; $i++) { $inputs += @("-i", $src) }
		Invoke-FFmpeg ($inputs + @("-filter_complex", $clip[1], "-map", "[out]") + $encode + @($dst))
		$got = & ffprobe -v error -show_entries format=duration -of csv=p=0 $dst
		if (-not "$got".Trim() -or (Num "$got") -le 0) { throw "$dst came out empty" }
	}
	$line = "{0,-9} {1,9}  {2,9}  {3,7}  {4,7}" -f $name, (Str $S), (Str $L), (Str $E), (Str $X)
	$report += $line
	Write-Host ("$line   -> loop is {0}s" -f (Str ($E - $L - $F)))
}

if (-not $FullOnly) {
	$report | Set-Content -Encoding UTF8 (Join-Path $OutDir "cuts used.txt")
	Write-Host "`nClips are in $OutDir"
}
