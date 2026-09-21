# Invoke-DispatchAll.ps1 — 觸發全部 workflow 並輪詢到結束
# 用法:
#   pwsh scripts/Invoke-DispatchAll.ps1          # 觸發並等待全部結束
#   pwsh scripts/Invoke-DispatchAll.ps1 -Watch   # 只輪詢現有 runs,不觸發
[CmdletBinding()]
param(
    [switch]$Watch,
    [int]$TimeoutMinutes = 40
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

# 所有 workflow 檔 (排除已 disabled)
$workflows = Get-ChildItem '.github/workflows' -Filter '*.yml' | Sort-Object Name
Write-Host "發現 $($workflows.Count) 個 workflow:" -ForegroundColor Cyan
$workflows | ForEach-Object { Write-Host "  - $($_.Name)" }

if (-not $Watch) {
    Write-Host "`n觸發全部 workflow..." -ForegroundColor Cyan
    foreach ($w in $workflows) {
        # workflow 名稱 = 檔名去副檔名
        & gh workflow run $w.Name --ref main 2>&1 | Out-String | Write-Host
        if ($LASTEXITCODE -ne 0) { Write-Host "  [WARN] 觸發 $($w.Name) 失敗" -ForegroundColor Yellow }
        Start-Sleep -Seconds 2
    }
    Start-Sleep -Seconds 10
}

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
while ($true) {
    $runs = & gh run list --limit 100 --json databaseId,name,status,conclusion,workflowName,createdAt 2>$null | ConvertFrom-Json
    $active = $runs | Where-Object { $_.status -ne 'completed' }
    $done = $runs | Where-Object { $_.status -eq 'completed' }

    Write-Host ("`n[{0}] 進行中: {1} / 已完成: {2}" -f (Get-Date -Format 'HH:mm:ss'), $active.Count, $done.Count) -ForegroundColor Cyan
    $runs | Select-Object -First 12 | ForEach-Object {
        $mark = if ($_.status -eq 'completed') {
            if ($_.conclusion -eq 'success') { '[OK]  ' } elseif ($_.conclusion -eq 'failure') { '[FAIL]' } else { "[other]" }
        } else { '[....]' }
        Write-Host ("  {0} {1}  {2}  {3}" -f $mark, $_.workflowName, $_.status, $_.conclusion)
    }

    if ($active.Count -eq 0 -and $done.Count -ge $workflows.Count) { break }
    if ((Get-Date) -gt $deadline) { Write-Host "逾時,停止輪詢" -ForegroundColor Yellow; break }
    Start-Sleep -Seconds 30
}

# 最終結論: 以「每個 workflow 最新一輪 run」判定
Write-Host "`n================ 最終結果 ================" -ForegroundColor Cyan
$allOk = $true
foreach ($w in $workflows) {
    # gh workflow list 顯示的名稱是 yml 內 name:
    $latest = & gh run list --workflow $w.Name --limit 1 --json conclusion,status,workflowName,databaseId 2>$null | ConvertFrom-Json
    if ($latest -and $latest[0].status -eq 'completed' -and $latest[0].conclusion -eq 'success') {
        Write-Host "  [OK]   $($w.Name)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $($w.Name) ($($latest[0].conclusion))" -ForegroundColor Red
        $allOk = $false
    }
}
if ($allOk) { Write-Host "`n全部 workflow 綠燈通過!" -ForegroundColor Green; exit 0 }
else { Write-Host "`n尚有失敗的 workflow" -ForegroundColor Red; exit 1 }
