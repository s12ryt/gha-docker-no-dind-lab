# Invoke-Validate.ps1 — 本地驗證 workflow 檔 (無需 Docker)
# 用途:
#   1. YAML 語法解析 (powershell 內建)
#   2. yamllint 風格檢查 (有 python 就用,失敗可 -SkipYamllint)
#   3. actionlint 靜態檢查 (自動下載 binary 到 .tools/)
#   4. 專案自訂規則: 每個 workflow 必須有 name/on/workflow_dispatch/jobs;
#      禁止 docker:dind;禁止 --privileged;必須 runs-on: ubuntu-latest
[CmdletBinding()]
param(
    [switch]$SkipYamllint,
    [switch]$SkipActionlint
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$WorkflowsDir = Join-Path $RepoRoot '.github/workflows'
$ToolsDir = Join-Path $RepoRoot '.tools'
$failures = @()

function Add-Failure([string]$msg) {
    $script:failures += $msg
    Write-Host "  [FAIL] $msg" -ForegroundColor Red
}

function Add-Ok([string]$msg) {
    Write-Host "  [OK]   $msg" -ForegroundColor Green
}

Write-Host "=== 1. YAML 語法解析 ===" -ForegroundColor Cyan
$files = Get-ChildItem $WorkflowsDir -Filter '*.yml' | Sort-Object Name
if ($files.Count -eq 0) { throw "找不到任何 workflow yml" }
foreach ($f in $files) {
    try {
        $null = Get-Content $f.FullName -Raw | ConvertFrom-Yaml -ErrorAction Stop
        Add-Ok "$($f.Name) YAML 解析通過"
    } catch [System.Management.Automation.CommandNotFoundException] {
        # 沒有 ConvertFrom-Yaml 模組時退回 python -c yaml.safe_load
        $py = Get-Command python -ErrorAction SilentlyContinue
        if ($py) {
            $code = "import yaml,sys; yaml.safe_load(open(sys.argv[1], encoding='utf-8'))" 
            & python -c $code $f.FullName
            if ($LASTEXITCODE -eq 0) { Add-Ok "$($f.Name) YAML 解析通過 (python)" }
            else { Add-Failure "$($f.Name) YAML 解析失敗 (python)" }
        } else {
            Add-Failure "無法解析 $($f.Name): 需要 ConvertFrom-Yaml 模組或 python"
        }
    } catch {
        Add-Failure "$($f.Name) YAML 解析失敗: $($_.Exception.Message)"
    }
}

Write-Host "`n=== 2. 專案自訂規則 ===" -ForegroundColor Cyan
foreach ($f in $files) {
    $raw = Get-Content $f.FullName -Raw
    $py = Get-Command python -ErrorAction SilentlyContinue
    $parsed = $null
    try { $parsed = Get-Content $f.FullName -Raw | ConvertFrom-Yaml -ErrorAction Stop } catch {}
    if (-not $parsed -and $py) {
        # 用 python 轉 json 再讀
        $json = & python -c "import yaml,sys,json; print(json.dumps(yaml.safe_load(open(sys.argv[1], encoding='utf-8'))))" $f.FullName 2>$null
        if ($LASTEXITCODE -eq 0 -and $json) { $parsed = $json | ConvertFrom-Json }
    }
    if ($parsed) {
        if ($parsed.name) { Add-Ok "$($f.Name): name = $($parsed.name)" } else { Add-Failure "$($f.Name): 缺 name" }
        if ($parsed.'on' -or $parsed.True -or $parsed.on) { } else { Add-Failure "$($f.Name): 缺 on" }
        if ($parsed.jobs) { Add-Ok "$($f.Name): jobs = $($parsed.jobs.PSObject.Properties.Name -join ', ')" } else { Add-Failure "$($f.Name): 缺 jobs" }
        # on 是 PowerShell 自動變數,ConvertFrom-Yaml 的 on 會變 True 鍵
        $onKey = if ($parsed.PSObject.Properties.Name -contains 'on') { 'on' } elseif ($parsed.PSObject.Properties.Name -contains 'True') { 'True' } else { $null }
        if ($onKey) {
            $onVal = $parsed.$onKey
            $hasDispatch = if ($onKey -eq 'True') { $onVal.PSObject.Properties.Name -contains 'workflow_dispatch' } else { $onVal -is [string] -or $onVal.PSObject.Properties.Name -contains 'workflow_dispatch' }
            if ($hasDispatch) { Add-Ok "$($f.Name): workflow_dispatch 已定義" } else { Add-Failure "$($f.Name): 缺 workflow_dispatch 觸發" }
        } else { Add-Failure "$($f.Name): 無法解析 on 區塊" }
        foreach ($jobName in $parsed.jobs.PSObject.Properties.Name) {
            $job = $parsed.jobs.$jobName
            $label = '{0}/{1}' -f $f.Name, $jobName
            if ($job.'runs-on' -eq 'ubuntu-latest') { Add-Ok "${label}: runs-on ubuntu-latest" }
            else { Add-Failure ("{0}: runs-on 應為 ubuntu-latest,實際 {1}" -f $label, $job.'runs-on') }
        }
    } else {
        Add-Failure "$($f.Name): 無法解析 YAML 結構做規則檢查"
    }
    # 禁用規則 (純文字掃描,最可靠)
    if ($raw -match 'docker:dind') { Add-Failure "$($f.Name): 偵測到 docker:dind (禁用)" } else { Add-Ok "$($f.Name): 無 docker:dind" }
    if ($raw -match '--privileged') { Add-Failure "$($f.Name): 偵測到 --privileged (禁用)" } else { Add-Ok "$($f.Name): 無 --privileged" }
}

Write-Host "`n=== 3. yamllint 風格檢查 ===" -ForegroundColor Cyan
if ($SkipYamllint) {
    Write-Host "  [SKIP] -SkipYamllint 指定" -ForegroundColor Yellow
} else {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) {
        Write-Host "  [SKIP] 無 python,跳過 yamllint" -ForegroundColor Yellow
    } else {
        & python -m pip install --quiet --disable-pip-version-check yamllint 2>$null
        & python -m yamllint -d relaxed $WorkflowsDir
        if ($LASTEXITCODE -eq 0) { Add-Ok "yamllint 全數通過" } else { Add-Failure "yamllint 有警告/錯誤 (relaxed 模式)" }
    }
}

Write-Host "`n=== 4. actionlint 靜態檢查 ===" -ForegroundColor Cyan
if ($SkipActionlint) {
    Write-Host "  [SKIP] -SkipActionlint 指定" -ForegroundColor Yellow
} else {
    $actionlint = Join-Path $ToolsDir 'actionlint.exe'
    if (-not (Test-Path $actionlint)) {
        New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
        Write-Host "  下載 actionlint 到 .tools/ ..."
        $rel = Invoke-RestMethod 'https://api.github.com/repos/rhysd/actionlint/releases/latest'
        $asset = $rel.assets | Where-Object { $_.name -match 'windows_amd64\.zip$' } | Select-Object -First 1
        if (-not $asset) { $asset = $rel.assets | Where-Object { $_.name -match 'windows-amd64\.zip$' } | Select-Object -First 1 }
        if (-not $asset) { throw "找不到 actionlint windows asset。可用資產: $($rel.assets.name -join ', ')" }
        $zip = Join-Path $env:TEMP $asset.name
        Invoke-WebRequest $asset.browser_download_url -OutFile $zip
        Expand-Archive $zip -DestinationPath $ToolsDir -Force
        Remove-Item $zip -Force
    }
    & $actionlint -version
    # Windows 下傳目錄會報 "Incorrect function",改逐一傳檔案
    $ymlFiles = (Get-ChildItem $WorkflowsDir -Filter '*.yml' | ForEach-Object { $_.FullName })
    & $actionlint -shellcheck= -pyflakes= @($ymlFiles) 2>&1 | Out-String | Write-Host
    if ($LASTEXITCODE -eq 0) { Add-Ok "actionlint 全數通過" } else { Add-Failure "actionlint 報告問題 (見上方輸出)" }
}

Write-Host "`n================ 結果 ================" -ForegroundColor Cyan
if ($failures.Count -eq 0) {
    Write-Host "全部通過 ($($files.Count) 個 workflow)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "失敗 $($failures.Count) 項:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}
