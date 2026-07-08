param(
    [string]$ParityMatrixPath = ".\\artifacts\\presentation_parity_matrix.md",
    [string]$DemoChecklistPath = ".\\artifacts\\hardware\\demo_checklist_log.md",
    [string]$SignoffReportPath = ".\\artifacts\\hardware\\signoff_report.md",
    [switch]$RunBoardSignoff,
    [string]$LatencyCsvPath = ".\\artifacts\\hardware\\latency_samples.csv",
    [double]$LatencyTargetMs = 50.0
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Finalize Presentation Sign-off" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

function Get-LatencyEvidenceStatus {
    param(
        [string]$ReportText
    )

    $m = [regex]::Match($ReportText, '(?m)^-\s+Latency evidence status:\s+([A-Z_]+)\s*$')
    if ($m.Success) {
        return $m.Groups[1].Value
    }

    return "MISSING"
}

if ($RunBoardSignoff) {
    if (-not (Test-Path ".\\scripts\\hardware\\run_board_signoff.ps1")) {
        Write-Error "Missing scripts/hardware/run_board_signoff.ps1"
    }

    Write-Host "Running board sign-off pipeline first..." -ForegroundColor Yellow
    & .\\scripts\\hardware\\run_board_signoff.ps1 -LatencyCsvPath $LatencyCsvPath -LatencyTargetMs $LatencyTargetMs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Board sign-off pipeline failed. Finalization cannot continue."
    }
}

if (-not (Test-Path $ParityMatrixPath)) {
    Write-Error "Missing parity matrix: $ParityMatrixPath"
}
if (-not (Test-Path $DemoChecklistPath)) {
    Write-Error "Missing checklist log: $DemoChecklistPath"
}
if (-not (Test-Path $SignoffReportPath)) {
    Write-Error "Missing sign-off report: $SignoffReportPath"
}

$parity = Get-Content $ParityMatrixPath -Raw
$checklist = Get-Content $DemoChecklistPath -Raw
$report = Get-Content $SignoffReportPath -Raw

$openChecks = [regex]::Matches($checklist, "(?m)^\s*-\s*\[\s\]") | Measure-Object | Select-Object -ExpandProperty Count
$latencyStatus = Get-LatencyEvidenceStatus -ReportText $report
$latencyPass = $latencyStatus -eq "PASS"
$templateData = $latencyStatus -eq "TEMPLATE_DATA"

$reportTime = (Get-Item $SignoffReportPath).LastWriteTimeUtc
$csvTime = (Get-Item $LatencyCsvPath).LastWriteTimeUtc
$checklistTime = (Get-Item $DemoChecklistPath).LastWriteTimeUtc
$reportIsFresh = ($reportTime -ge $csvTime) -and ($reportTime -ge $checklistTime)

if (-not $reportIsFresh) {
    Write-Host "" 
    Write-Host "Sign-off cannot be finalized yet." -ForegroundColor Yellow
    Write-Host "- Sign-off report is stale relative to checklist/latency evidence." -ForegroundColor Yellow
    Write-Host "- Re-run: .\\scripts\\hardware\\run_board_signoff.ps1" -ForegroundColor Yellow
    exit 1
}

if ($openChecks -gt 0 -or -not $latencyPass) {
    Write-Host ""
    Write-Host "Sign-off cannot be finalized yet." -ForegroundColor Yellow
    Write-Host ("- Unchecked demo items: {0}" -f $openChecks) -ForegroundColor Yellow

    if ($templateData) {
        Write-Host "- Latency evidence is template data; replace with real board measurements." -ForegroundColor Yellow
    } elseif (-not $latencyPass) {
        Write-Host ("- Latency evidence is not PASS yet (current status: {0})." -f $latencyStatus) -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Next:" -ForegroundColor Cyan
    Write-Host "1) Complete all checklist [ ] items in artifacts/hardware/demo_checklist_log.md"
    Write-Host "2) Provide real measurements in artifacts/hardware/latency_samples.csv"
    Write-Host "3) Run: .\\scripts\\hardware\\run_board_signoff.ps1"
    Write-Host "4) Re-run: .\\scripts\\hardware\\finalize_signoff.ps1"
    exit 1
}

$updated = $parity
$updated = $updated -replace "\| C-006 \|([^\n]*?)\| In Progress \|", "| C-006 |$1| Satisfied |"
$updated = $updated -replace "\| C-008 \|([^\n]*?)\| In Progress \|", "| C-008 |$1| Satisfied |"

$stamp = Get-Date -Format "yyyy-MM-dd"
$decisionLine = "- " + $stamp + " C-006 and C-008 marked Satisfied after board evidence and demo checklist completion."
if ($updated -notmatch [regex]::Escape($decisionLine)) {
    $updated = $updated -replace "(?m)^## Execution Checklist", ($decisionLine + "`r`n`r`n## Execution Checklist")
}

Set-Content -Path $ParityMatrixPath -Value $updated -Encoding ASCII

Write-Host ""
Write-Host "Final sign-off complete." -ForegroundColor Green
Write-Host "Updated: artifacts/presentation_parity_matrix.md" -ForegroundColor Green
exit 0
