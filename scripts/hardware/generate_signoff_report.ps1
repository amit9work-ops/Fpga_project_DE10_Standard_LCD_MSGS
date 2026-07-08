param(
    [string]$OutPath = ".\\artifacts\\hardware\\signoff_report.md",
    [string]$LatencyCsvPath = ".\\artifacts\\hardware\\latency_samples.csv",
    [double]$LatencyTargetMs = 50.0
)

$ErrorActionPreference = "Stop"

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$root = Get-Location

$verifyResult = "NOT_RUN"
$latencyResult = "NOT_AVAILABLE"
$latencySummary = @()
$placeholderDetected = $false

if (Test-Path ".\\verify_all.ps1") {
    $verifyResult = "AVAILABLE"
}

if (Test-Path $LatencyCsvPath) {
    try {
        $rows = Import-Csv -Path $LatencyCsvPath
        $vals = @()
        foreach ($r in $rows) {
            if (-not $r.latency_ms) { continue }
            if ($r.notes -and ($r.notes -match "replace_with_real_measurement")) {
                $placeholderDetected = $true
            }
            $d = 0.0
            if ([double]::TryParse($r.latency_ms, [ref]$d)) {
                $vals += $d
            }
        }

        if ($vals.Count -gt 0) {
            $m = $vals | Measure-Object -Average -Minimum -Maximum
            $max = [math]::Round($m.Maximum, 3)
            $allZero = ($vals | Where-Object { $_ -ne 0 }).Count -eq 0

            if ($placeholderDetected -or $allZero) {
                $latencyResult = "TEMPLATE_DATA"
            }
            else {
                $latencyResult = if ($max -le $LatencyTargetMs) { "PASS" } else { "FAIL" }
            }

            $latencySummary += "- Samples: $($vals.Count)"
            $latencySummary += "- Mean ms: $([math]::Round($m.Average,3))"
            $latencySummary += "- Min ms:  $([math]::Round($m.Minimum,3))"
            $latencySummary += "- Max ms:  $max"
            $latencySummary += "- Target ms: <= $LatencyTargetMs"
            $latencySummary += "- Result: $latencyResult"
            if ($latencyResult -eq "TEMPLATE_DATA") {
                $latencySummary += "- Warning: replace template rows with real board measurements before sign-off."
            }
        }
        else {
            $latencyResult = "NO_VALID_SAMPLES"
        }
    }
    catch {
        $latencyResult = "CSV_PARSE_ERROR"
    }
}

$report = @()
$report += "# Sign-off Report"
$report += ""
$report += "Generated: $timestamp"
$report += "Workspace: $root"
$report += ""
$report += "## Status Summary"
$report += ""
$report += "- verify_all availability: $verifyResult"
$report += "- Latency evidence status: $latencyResult"
$report += ""
$report += "## Demo Checklist"
$report += ""
$report += "- [ ] FPGA programmed with current bitstream"
$report += "- [ ] HPS app launched and stable"
$report += "- [ ] IDLE -> HOME transition observed"
$report += "- [ ] HOME <-> MSG navigation verified"
$report += "- [ ] Timeout -> SLEEP behavior verified"
$report += "- [ ] Wake from SLEEP verified"
$report += ""
$report += "## Latency Evidence"
$report += ""
if ($latencySummary.Count -gt 0) {
    $report += $latencySummary
}
else {
    $report += "- No valid latency samples available yet."
}
$report += ""
$report += "## Notes"
$report += ""
$report += "- Attach scope/analyzer captures if presentation requires hardware timing proof."
$report += "- Update artifacts/presentation_parity_matrix.md (C-006, C-008) when evidence is complete."

$outDir = Split-Path -Parent $OutPath
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

Set-Content -Path $OutPath -Value $report -Encoding ASCII
Write-Host "Sign-off report generated: $OutPath" -ForegroundColor Green
