# Clone (or update to the latest commit of) every source tree under src/, and fetch the Opus DNN
# model data that the git tree of opus doesn't carry (upstream does this in autogen.sh/.bat).
#   ./fetch-sources.ps1            clone missing repos, fast-forward existing ones
#   ./fetch-sources.ps1 -NoUpdate  only clone what's missing
param([switch]$NoUpdate)
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'src'
New-Item -ItemType Directory -Force $src | Out-Null

# GitHub mirrors of gitlab.xiph.org (flac's primary home is GitHub).
$repos = [ordered]@{
  'ogg'        = 'https://github.com/xiph/ogg.git'
  'opus'       = 'https://github.com/xiph/opus.git'
  'opusfile'   = 'https://github.com/xiph/opusfile.git'
  'libopusenc' = 'https://github.com/xiph/libopusenc.git'
  'flac'       = 'https://github.com/xiph/flac.git'
  'opus-tools' = 'https://github.com/xiph/opus-tools.git'
}

foreach ($name in $repos.Keys) {
  $dir = Join-Path $src $name
  if (-not (Test-Path (Join-Path $dir '.git'))) {
    git clone $repos[$name] $dir
  } elseif (-not $NoUpdate) {
    git -C $dir pull --ff-only --tags
  }
  if ($LASTEXITCODE) { throw "git failed for $name" }
  # Full history + tags: the version strings come from `git describe`.
  "{0,-11} {1}" -f $name, (git -C $dir log -1 --format='%h %cs %s')
}

# Opus model data: autogen.sh names the archive by its SHA-256.
$opus = Join-Path $src 'opus'
$line = Select-String -Path (Join-Path $opus 'autogen.sh') -Pattern 'download_model\.sh\s+"?([0-9a-f]{64})' |
        Select-Object -First 1
if (-not $line) { throw 'Model hash not found in src/opus/autogen.sh' }
$hash = $line.Matches[0].Groups[1].Value
$tgz  = Join-Path $opus "opus_data-$hash.tar.gz"
$stamp = Join-Path $opus 'dnn\.model-stamp'

if ((Test-Path $stamp) -and ((Get-Content $stamp) -eq $hash)) {
  "opus model  $hash (already unpacked)"
  return
}
for ($i = 0; $i -lt 10; $i++) {
  if ((Test-Path $tgz) -and (Get-FileHash $tgz -Algorithm SHA256).Hash.ToLower() -eq $hash) { break }
  # media.xiph.org drops connections now and then; resume until the hash matches.
  curl.exe -sSL --retry 5 --retry-all-errors --connect-timeout 20 --speed-time 30 --speed-limit 1000 `
    -C - -o $tgz "https://media.xiph.org/opus/models/opus_data-$hash.tar.gz"
}
if ((Get-FileHash $tgz -Algorithm SHA256).Hash.ToLower() -ne $hash) {
  Remove-Item $tgz; throw 'Model download failed hash check'
}
tar -xzf $tgz -C $opus
if ($LASTEXITCODE) { throw 'Unpacking the model failed' }
Set-Content $stamp $hash
"opus model  $hash (unpacked)"
