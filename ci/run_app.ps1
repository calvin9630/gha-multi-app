param(
  [Parameter(Mandatory=$true)] [string]$AppName,
  [Parameter(Mandatory=$true)] [string]$Entry,
  [Parameter(Mandatory=$true)] [string]$ReqFile,
  [string]$PyVersion = "3.11",
  [string]$BaseWorkDir = "$env:USERPROFILE\AppDeploy"
)

$ErrorActionPreference = "Stop"

$AppRoot = Join-Path $BaseWorkDir $AppName
$CodeDir = Join-Path $AppRoot "code"
$VenvDir = Join-Path $AppRoot "venv"
$LogDir  = Join-Path $AppRoot "logs"

New-Item -ItemType Directory -Force -Path $AppRoot,$CodeDir,$LogDir | Out-Null

Write-Host "== Sync code to $CodeDir =="
robocopy "$PWD" "$CodeDir" /MIR /XD ".git" ".github" ".venv" ".pytest_cache" "node_modules" | Out-Null

if (-not (Test-Path $VenvDir)) {
  Write-Host "== Create venv ($PyVersion) at $VenvDir =="
  py -$PyVersion -m venv $VenvDir
}

$Pip = Join-Path $VenvDir "Scripts\pip.exe"
$Py  = Join-Path $VenvDir "Scripts\python.exe"
& $Pip install --upgrade pip wheel > $null

$ReqPath = Join-Path $CodeDir $ReqFile
if (-not (Test-Path $ReqPath)) { throw "Requirements file not found: $ReqPath" }

$HashFile = Join-Path $AppRoot "requirements.sha256"
$NewHash = (Get-FileHash $ReqPath -Algorithm SHA256).Hash
$NeedInstall = $true
if (Test-Path $HashFile) {
  $OldHash = Get-Content $HashFile -Raw
  if ($OldHash -eq $NewHash) { $NeedInstall = $false }
}

if ($NeedInstall) {
  Write-Host "== Installing dependencies for $AppName =="
  & $Pip install -r $ReqPath
  $NewHash | Out-File $HashFile -Encoding ascii
} else {
  Write-Host "== Dependencies unchanged. Skip install =="
}

$Date = (Get-Date).ToString("yyyy-MM-dd")
$LogFile = Join-Path $LogDir "$($AppName)_$Date.log"
$EntryPath = Join-Path $CodeDir $Entry

if (-not (Test-Path $EntryPath)) { throw "Entry script not found: $EntryPath" }

Write-Host "== Run $EntryPath =="
& $Py $EntryPath *>> $LogFile

Get-ChildItem $LogDir -Filter "$AppName*_*.log" |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } |
  Remove-Item -Force -ErrorAction SilentlyContinue

Write-Host "== Done. Log => $LogFile =="
