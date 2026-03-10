# copy_firebase_key.ps1
# Copies FIREBASE_SERVICE_ACCOUNT from her-ai-brain to her-ai-reflection and her-ai-briefing
# Run this after every deploy_phase_de.bat

$REGION = "ap-south-1"

Write-Host ""
Write-Host "Copying Firebase key to all Lambdas..." -ForegroundColor Cyan

# Step 1: Read all env vars from her-ai-brain as JSON object
$brainConfig = aws lambda get-function-configuration `
    --function-name her-ai-brain `
    --region $REGION `
    --output json | ConvertFrom-Json

$vars = $brainConfig.Environment.Variables

$groq    = $vars.GROQ_API_KEY
$serper  = $vars.SERPER_API_KEY  
$fb      = $vars.FIREBASE_SERVICE_ACCOUNT

if (-not $fb) {
    Write-Host "ERROR: FIREBASE_SERVICE_ACCOUNT not found in her-ai-brain" -ForegroundColor Red
    exit 1
}

Write-Host "  OK - keys read from her-ai-brain" -ForegroundColor Green

# Step 2: Build env vars object for the other Lambdas
$envVars = @{
    Variables = @{
        GROQ_API_KEY               = $groq
        SERPER_API_KEY             = $serper
        FIREBASE_SERVICE_ACCOUNT   = $fb
    }
}
$envJson = $envVars | ConvertTo-Json -Compress -Depth 3

# Step 3: Update her-ai-reflection
Write-Host "  Updating her-ai-reflection..." -ForegroundColor Yellow
aws lambda update-function-configuration `
    --function-name her-ai-reflection `
    --region $REGION `
    --environment $envJson `
    --output text | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  OK - her-ai-reflection updated" -ForegroundColor Green
} else {
    Write-Host "  FAILED - her-ai-reflection" -ForegroundColor Red
}

# Step 4: Update her-ai-briefing
Write-Host "  Updating her-ai-briefing..." -ForegroundColor Yellow
aws lambda update-function-configuration `
    --function-name her-ai-briefing `
    --region $REGION `
    --environment $envJson `
    --output text | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  OK - her-ai-briefing updated" -ForegroundColor Green
} else {
    Write-Host "  FAILED - her-ai-briefing" -ForegroundColor Red
}

# Step 5: Update her-ai-content
Write-Host "  Updating her-ai-content..." -ForegroundColor Yellow
aws lambda update-function-configuration `
    --function-name her-ai-content `
    --region $REGION `
    --environment $envJson `
    --output text | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host "  OK - her-ai-content updated" -ForegroundColor Green }

# Step 6: Update her-ai-notifier
Write-Host "  Updating her-ai-notifier..." -ForegroundColor Yellow
aws lambda update-function-configuration `
    --function-name her-ai-notifier `
    --region $REGION `
    --environment $envJson `
    --output text | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host "  OK - her-ai-notifier updated" -ForegroundColor Green }

# Step 7: Update her-ai-strategy
Write-Host "  Updating her-ai-strategy..." -ForegroundColor Yellow
aws lambda update-function-configuration `
    --function-name her-ai-strategy `
    --region $REGION `
    --environment $envJson `
    --output text | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host "  OK - her-ai-strategy updated" -ForegroundColor Green }

Write-Host ""
Write-Host "Done. Firebase key synced to all 6 Lambdas." -ForegroundColor Green
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
