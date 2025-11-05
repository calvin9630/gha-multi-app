param(
  [Parameter(Mandatory = $true)] [string]$AppName,
  [Parameter(Mandatory = $true)] [string]$Entry,    # 例如: "apps/appC/main.py"
  [Parameter(Mandatory = $true)] [string]$ReqFile,  # 例如: "apps/appC/requirements.txt"
  [string]$PyVersion = "3.11",
  [string]$BaseWorkDir
)

$ErrorActionPreference = "Stop"

# ---- 路徑與環境：跨平台處理 ----
if (-not $BaseWorkDir -or $BaseWorkDir -eq "") {
  # Windows 用 USERPROFILE；Linux/Mac 用 HOME
  $home = if ($IsWindows) { $env:USERPROFILE } else { $env:HOME }
  $BaseWorkDir = Join-Path $home "AppDeploy"
}

$AppRoot = Join-Path $BaseWorkDir $AppName
$CodeDir = Join-Path $AppRoot "code"
$VenvDir = Join-Path $AppRoot "venv"
$LogDir  = Join-Path $AppRoot "logs"

# ---- 建立資料夾 ----
New-Item -ItemType Directory -Force -Path $AppRoot,$LogDir | Out-Null

# 重新同步 code：為了簡單與可預期，直接刪除重建 CodeDir（避免 rsync/robocopy 依賴）
if (Test-Path $CodeDir) { Remove-Item -Recurse -Force $CodeDir }
New-Item -ItemType Directory -Force -Path $CodeDir | Out-Null

Write-Host "== Sync code to $CodeDir =="
# 複製整個工作目錄到 CodeDir
Copy-Item -Path (Join-Path $PWD '*') -Destination $CodeDir -Recurse -Force -ErrorAction Stop

# 清掉不需要的目錄（跨平台做法）
@(".git", ".github", ".venv", ".pytest_cache", "node_modules") | ForEach-Object {
  $p = Join-Path $CodeDir $_
  if (Test-Path $p) { Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue }
}

# ---- 建立/取得 venv（跨平台）----
# 在 GitHub Actions 我們已用 actions/setup-python 指定版本，這裡直接用 PATH 中的 python
# 若你一定要用 py launcher（只在 Windows 有），可加判斷；這裡統一用 python 最穩定
if (-not (Test-Path $VenvDir)) {
  Write-Host "== Create venv at $VenvDir =="
  python -m venv "$VenvDir"
}

# venv 下可執行檔的子目錄：Windows 是 Scripts、Linux/Mac 是 bin
$VenvBin = if ($IsWindows) { Join-Path $VenvDir "Scripts" } else { Join-Path $VenvDir "bin" }
$Pip = Join-Path $VenvBin (if ($IsWindows) { "pip.exe" } else { "pip" })
$Py  = Join-Path $VenvBin (if ($IsWindows) { "python.exe" } else { "python" })

# 升級 pip / wheel
& $Pip install --upgrade pip wheel > $null

# ---- 安裝套件（以 requirements 的雜湊判斷是否需要重裝）----
$ReqPath = Join-Path $CodeDir $ReqFile
if (-not (Test-Path $ReqPath)) { throw "Requirements file not found: $ReqPath" }

$HashFile  = Join-Path $AppRoot "requirements.sha256"
$NewHash   = (Get-FileHash $ReqPath -Algorithm SHA256).Hash
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
$Date     = (Get-Date).ToString("yyyy-MM-dd")
$LogFile  = Join-Path $LogDir "$($AppName)_$Date.log"
$EntryPath = Join-Path $CodeDir $Entry
if (-not (Test-Path $EntryPath)) { throw "Entry script not found: $EntryPath" }

Write-Host "== Run $EntryPath =="
# 將 stdout/stderr 追加到每日 log
& $Py "$EntryPath" *>> "$LogFile"

# ---- 清理舊日誌（保留 14 天）----
Get-ChildItem $LogDir -Filter "$AppName*_*.log" |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } |
  Remove-Item -Force -ErrorAction SilentlyContinue

Write-Host "== Done. Log => $LogFile =="
