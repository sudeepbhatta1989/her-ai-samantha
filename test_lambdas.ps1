# test_lambdas.ps1
# Run this to verify all 3 Lambdas are working after the pinned-deps rebuild
# Usage: Right-click -> Run with PowerShell  OR  paste into Windows Terminal

$REGION = "ap-south-1"
$OUT = "C:\Users\sudee\Downloads\lambda_build"

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  Lambda Smoke Tests" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

# ── Test 1: her-ai-brain — get_streaks ────────────────────────
Write-Host "[1/4] Testing her-ai-brain (get_streaks)..." -ForegroundColor Yellow
$payload1 = '{"userId":"user1","action":"get_streaks"}' | ConvertTo-Json -Compress
# payload must be passed as literal JSON string
aws lambda invoke `
    --function-name her-ai-brain `
    --region $REGION `
    --payload '{"userId":"user1","action":"get_streaks"}' `
    --cli-binary-format raw-in-base64-out `
    "$OUT\test_streaks.json" | Out-Null
$result1 = Get-Content "$OUT\test_streaks.json" -Raw
Write-Host "Result: $result1" -ForegroundColor $(if ($result1 -match '"status":"ok"') {"Green"} else {"Red"})
Write-Host ""

# ── Test 2: her-ai-brain — chat message ────────────────────────
Write-Host "[2/4] Testing her-ai-brain (chat)..." -ForegroundColor Yellow
aws lambda invoke `
    --function-name her-ai-brain `
    --region $REGION `
    --payload '{"userId":"user1","message":"hi samantha, quick test"}' `
    --cli-binary-format raw-in-base64-out `
    "$OUT\test_chat.json" | Out-Null
$result2 = Get-Content "$OUT\test_chat.json" -Raw
$chatOk = $result2 -match '"reply"' -and $result2 -notmatch 'ImportModuleError' -and $result2 -notmatch 'errorMessage'
Write-Host "Result: $(if ($chatOk) {'PASS - Samantha replied'} else {$result2})" -ForegroundColor $(if ($chatOk) {"Green"} else {"Red"})
Write-Host ""

# ── Test 3: her-ai-briefing ────────────────────────────────────
Write-Host "[3/4] Testing her-ai-briefing..." -ForegroundColor Yellow
aws lambda invoke `
    --function-name her-ai-briefing `
    --region $REGION `
    --payload '{"user_id":"user1"}' `
    --cli-binary-format raw-in-base64-out `
    "$OUT\test_briefing.json" | Out-Null
$result3 = Get-Content "$OUT\test_briefing.json" -Raw
$briefOk = $result3 -match '"status":"ok"' -or $result3 -match '"status": "ok"'
Write-Host "Result: $(if ($briefOk) {'PASS - Briefing generated'} else {$result3})" -ForegroundColor $(if ($briefOk) {"Green"} else {"Red"})
Write-Host ""

# ── Test 4: her-ai-reflection ──────────────────────────────────
Write-Host "[4/4] Testing her-ai-reflection..." -ForegroundColor Yellow
aws lambda invoke `
    --function-name her-ai-reflection `
    --region $REGION `
    --payload '{"user_id":"user1"}' `
    --cli-binary-format raw-in-base64-out `
    "$OUT\test_reflection.json" | Out-Null
$result4 = Get-Content "$OUT\test_reflection.json" -Raw
$reflOk = $result4 -match '"status":"ok"' -or $result4 -match '"status": "ok"' -or $result4 -match '"statusCode": 200'
Write-Host "Result: $(if ($reflOk) {'PASS - Reflection generated'} else {$result4})" -ForegroundColor $(if ($reflOk) {"Green"} else {"Red"})
Write-Host ""

# ── Summary ────────────────────────────────────────────────────
Write-Host "====================================================" -ForegroundColor Cyan
$allPass = $chatOk -and $briefOk -and $reflOk
if ($allPass) {
    Write-Host "  ALL TESTS PASSED" -ForegroundColor Green
    Write-Host "  App should be fully working now." -ForegroundColor Green
} else {
    Write-Host "  SOME TESTS FAILED - check results above" -ForegroundColor Red
    Write-Host "  If you see 'ImportModuleError' -> Firebase key missing" -ForegroundColor Yellow
    Write-Host "  If you see 'cryptography' error -> redeploy with pinned deps" -ForegroundColor Yellow
}
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Full results saved to: $OUT\" -ForegroundColor Gray
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
