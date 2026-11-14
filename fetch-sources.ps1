# Get the sources for both build channels:
#   src/         latest: master of every repo
#   src-stable/  stable: newest release tag of every repo (git worktrees of the src/ clones)
# and the Opus DNN model data each opus tree needs (upstream fetches it in autogen.sh/.bat).
#
#   ./fetch-sources.ps1                     latest (the default): clone or pull master into src/
#   ./fetch-sources.ps1 -Channel stable     fallback: src-stable/ at the newest release tags
#                                           (src/ clones are fetched, not pulled)
#   ./fetch-sources.ps1 -Channel all        both
#   ./fetch-sources.ps1 -NoUpdate           only create what's missing, leave the rest as is
#   ./fetch-sources.ps1 -Channel stable -Pin @{ opus = 'v1.6' }   use this tag instead of the newest
param(
  [ValidateSet('latest', 'stable', 'all')] [string]$Channel = 'latest',
  [switch]$NoUpdate,
  [hashtable]$Pin = @{}
)
$ErrorActionPreference = 'Stop'
$root   = $PSScriptRoot
$src    = Join-Path $root 'src'
$stable = Join-Path $root 'src-stable'

# GitHub mirrors of gitlab.xiph.org (flac's primary home is GitHub).
$repos = [ordered]@{
  'ogg'        = 'https://github.com/xiph/ogg.git'
  'opus'       = 'https://github.com/xiph/opus.git'
  'opusfile'   = 'https://github.com/xiph/opusfile.git'
  'libopusenc' = 'https://github.com/xiph/libopusenc.git'
  'flac'       = 'https://github.com/xiph/flac.git'
  'opus-tools' = 'https://github.com/xiph/opus-tools.git'
}
foreach ($k in $Pin.Keys) { if (-not $repos.Contains($k)) { throw "-Pin: unknown repo '$k'" } }

function Invoke-Git { git @args; if ($LASTEXITCODE) { throw "git $args failed" } }

# Newest release tag: v1.2.3 or 1.2.3; no rc/beta/alpha tags.
function Get-ReleaseTag([string]$dir) {
  $tag = git -C $dir tag --sort=-v:refname | Where-Object { $_ -match '^v?\d+(\.\d+)+$' } | Select-Object -First 1
  if (-not $tag) { throw "No release tag in $dir" }
  $tag
}

# Opus model data: autogen.sh names the archive by its SHA-256. Each opus tree gets its own copy,
# since a release and master can need different models.
function Install-OpusModel([string]$opus) {
  $line = Select-String -Path (Join-Path $opus 'autogen.sh') -Pattern 'download_model\.sh\s+"?([0-9a-f]{64})' |
          Select-Object -First 1
  if (-not $line) { throw "Model hash not found in $opus/autogen.sh" }
  $hash  = $line.Matches[0].Groups[1].Value
  $tgz   = Join-Path $opus "opus_data-$hash.tar.gz"
  $stamp = Join-Path $opus 'dnn\.model-stamp'
  if ((Test-Path $stamp) -and ((Get-Content $stamp) -eq $hash)) { return "model $hash (already unpacked)" }

  # The other tree may already have the archive.
  foreach ($other in (Join-Path $src 'opus'), (Join-Path $stable 'opus')) {
    $cand = Join-Path $other "opus_data-$hash.tar.gz"
    if (-not (Test-Path $tgz) -and (Test-Path $cand)) { Copy-Item $cand $tgz }
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
  "model $hash (unpacked)"
}

$doLatest = $Channel -in 'all', 'latest'
$doStable = $Channel -in 'all', 'stable'

# --- src/: the clones (needed by both channels) ---------------------------------------------------
New-Item -ItemType Directory -Force $src | Out-Null
foreach ($name in $repos.Keys) {
  $dir = Join-Path $src $name
  if (-not (Test-Path (Join-Path $dir '.git'))) {
    # Full history + tags: version strings come from `git describe`, stable needs the tags.
    Invoke-Git clone $repos[$name] $dir
  } elseif (-not $NoUpdate) {
    if ($doLatest) { Invoke-Git -C $dir pull -q --ff-only --tags }
    else           { Invoke-Git -C $dir fetch -q --tags }
  }
}

if ($doLatest) {
  "== latest (src/)"
  foreach ($name in $repos.Keys) {
    "  {0,-11} {1}" -f $name, (git -C (Join-Path $src $name) log -1 --format='%h %cs %s')
  }
  "  opus        " + (Install-OpusModel (Join-Path $src 'opus'))
}

# --- src-stable/: worktrees at release tags -------------------------------------------------------
if ($doStable) {
  "== stable (src-stable/)"
  New-Item -ItemType Directory -Force $stable | Out-Null
  foreach ($name in $repos.Keys) {
    $clone = Join-Path $src $name
    $dir   = Join-Path $stable $name
    $tag   = if ($Pin.ContainsKey($name)) { $Pin[$name] } else { Get-ReleaseTag $clone }
    if (-not (Test-Path (Join-Path $dir '.git'))) {
      Invoke-Git -C $clone worktree prune
      Invoke-Git -C $clone worktree add -q --detach $dir $tag
    } elseif (-not $NoUpdate -or $Pin.ContainsKey($name)) {
      Invoke-Git -C $dir checkout -q --detach $tag
    }
    "  {0,-11} {1,-8} {2}" -f $name, (git -C $dir describe --tags --exact-match 2>$null), (git -C $dir log -1 --format='%h %cs')
  }
  "  opus        " + (Install-OpusModel (Join-Path $stable 'opus'))
}
