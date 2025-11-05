param(
  [Parameter(Mandatory = $true)] [string]$AppName,
  [Parameter(Mandatory = $true)] [string]$Entry,    # 例: "apps/appC/main.py"
  [Parameter(Mandatory = $true)] [string]$ReqFile,  # 例: "apps/appC/requirements.txt"
  [string]$PyVersion = "3.11",
  [string]$BaseWorkDir
)

$ErrorActionPreference = "Stop"

# ---- 基底工作目錄（跨平台）----
if (-not $BaseWorkDir -or $BaseWorkDir -eq "") {
  $myHome = if ($IsWindows) { $env:USERPROFILE } else { $env:HOME }
  $BaseWorkDir = Join-Path $myHome "AppDeploy"
}

$AppRoot = Join-Path $BaseWorkDir $AppName
$CodeDir = Join-Path $AppRoot "code"
$VenvDir = Join-Path $AppRoot "venv"
$LogDir  = Join-Path $AppRoot "logs"

# ---- 建立資料夾 ----
New-Item -ItemType Directory -Force -Path $AppRoot,$LogDir | Out-Null

# 重新同步程式碼：刪掉舊的 code 再複製
if (Test-Path $CodeDir) { Remove-Item -Recurse -Force $CodeDir }
New-Item -ItemType Directory -Force -Path $CodeDir | Out-Null

Write-Host "== Sync code to $CodeDir =="
Copy-Item -Path (Join-Path $PWD '*') -Destination $CodeDir -Recurse -Force -ErrorAction Stop

# 排除不需要的資料夾
@(".git", ".github", ".venv", ".pytest_cache", "node_modules") | ForEach-Object {
  $p = Join-Path $CodeDir $_
  if (Test-Path $p) { Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue }
}

# ---- 建立 venv（用 PATH 中的 python）----
if (-not (Test-Path $VenvDir)) {
  Write-Host "== Create venv at $VenvDir =="
  python -m venv "$VenvDir"
}

# 依平臺決定 venv 子目錄與可執行檔名稱（用傳統 if/else）
if ($IsWindows) {
  $VenvBin = Join-Path $VenvDir "Scripts"
  $pipName = "pip.exe"
  $pyName  = "python.exe"
} else {
  $VenvBin = Join-Path $VenvDir "bin"
  $pipName = "pip"
  $pyName  = "python"
}
$Pip = Join-Path $VenvBin $pipName
$Py  = Join-Path $VenvBin $pyName

# 升級 pip / wheel
& $Pip install --upgrade pip wheel > $null

# ---- 安裝套件（依 requirements 雜湊判斷）----
$ReqPath = Join-Path $CodeDir $ReqFile
if (-not (Test-Path $ReqPath)) { throw "Requirements file not found: $ReqPath" }

$HashFile   = Join-Path $AppRoot "requirements.sha256"
$NewHash    = (Get-FileHash $ReqPath -Algorithm SHA256).Hash
$NeedInstall = $true
if (Test-Path $HashFile) {
  $OldHash = Get-Content $HashFile -Raw
  if ($OldHash -eq $NewHash) { $NeedInstall = $false }
}

if ($NeedInstall) {
  Write-Host "== Installing dependencies for $AppName =="
  & $Pip install -r "$ReqPath"
  $NewHash | Out-File $HashFile -Encoding ascii
} else {
  Write-Host "== Dependencies unchanged. Skip install =="
}

# ---- 執行主程式並寫日誌 ----
$Date      = (Get-Date).ToString("yyyy-MM-dd")
$LogFile   = Join-Path $LogDir "$($AppName)_$Date.log"
$EntryPath = Join-Path $CodeDir $Entry
if (-not (Test-Path $EntryPath)) { throw "Entry script not found: $EntryPath" }

Write-Host "== Run $EntryPath =="
& $Py "$EntryPath" *>> "$LogFile"

# ---- 清理 14 天前的舊日誌 ----
Get-ChildItem $LogDir -Filter "$AppName*_*.log" |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } |
  Remove-Item -Force -ErrorAction SilentlyContinue

Write-Host "== Done. Log => $LogFile =="
