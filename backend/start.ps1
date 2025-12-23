<#
.SYNOPSIS
    Automated Server Startup Script
.DESCRIPTION
    Prompts for video password, starts Node server, starts Cloudflare tunnel,
    and updates GitHub with the new endpoint.
.NOTES
    Requires 'cloudflared' in PATH.
    Requires 'GITHUB_TOKEN' env variable.
    Save this file as UTF-8 (WITHOUT BOM).
#>

param()

# ===================== CONFIGURATION =====================
$GithubRepo = "goutham-11-16/tv"
$GithubBranch = "main"
$GithubFile = "server_endpoint.json"
$LocalPort = 3000
# ========================================================

# ===================== ENV CHECK =========================
# ===================== ENV CHECK =========================
if (-not $env:GITHUB_TOKEN) {
    Write-Warning "GITHUB_TOKEN environment variable is missing. GitHub update will be skipped."
    # Continue anyway to start server/tunnel
}
# ========================================================
# ========================================================

# ================= PASSWORD INPUT ========================
if ($env:VIDEO_PASSWORD) {
    $videoPassword = $env:VIDEO_PASSWORD
    Write-Host "Using Video Password from Environment Variable." -ForegroundColor Green
}
else {
    Write-Host "Enter Video Encryption Password (Hidden): " -NoNewline -ForegroundColor Cyan
    $securePass = Read-Host -AsSecureString
    $videoPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
    )
    Write-Host "`nPassword captured." -ForegroundColor Green
}
# ========================================================

# ================= START NODE SERVER =====================
Write-Host "Starting Auth Server on Port $LocalPort..." -ForegroundColor Cyan
$env:VIDEO_PASSWORD = $videoPassword

$nodeProcess = Start-Process `
    -FilePath "node" `
    -ArgumentList "server.js" `
    -PassThru `
    -NoNewWindow `
    -RedirectStandardOutput "server.log" `
    -RedirectStandardError  "server_err.log"

if (-not $nodeProcess.Id) {
    Write-Error "Failed to start Node.js server."
    exit 1
}

Write-Host "Server started (PID: $($nodeProcess.Id)). Log: server.log" -ForegroundColor Green
# ========================================================

# ================= START CLOUDFLARE ======================
Write-Host "Starting Cloudflare Tunnel..." -ForegroundColor Cyan

$tunnelLog = "tunnel.log"
if (Test-Path $tunnelLog) { Remove-Item $tunnelLog -Force }

$tunnelProcess = Start-Process `
    -FilePath "cloudflared" `
    -ArgumentList "tunnel --url http://localhost:$LocalPort" `
    -PassThru `
    -NoNewWindow `
    -RedirectStandardOutput "tunnel_stdout.log" `
    -RedirectStandardError  $tunnelLog

if (-not $tunnelProcess.Id) {
    Stop-Process -Id $nodeProcess.Id -Force
    Write-Error "Failed to start Cloudflare tunnel."
    exit 1
}
# ========================================================

# ================= CAPTURE TUNNEL URL ===================
Write-Host "Waiting for Tunnel URL..." -NoNewline
$tunnelUrl = $null

for ($i = 0; $i -lt 30; $i++) {
    if (Test-Path $tunnelLog) {
        $log = Get-Content $tunnelLog -Raw
        if ($log -match "https://[a-zA-Z0-9-]+\.trycloudflare\.com") {
            $tunnelUrl = $matches[0]
            break
        }
    }
    Start-Sleep 1
    Write-Host "." -NoNewline
}

if (-not $tunnelUrl) {
    Write-Error "`nFailed to capture Tunnel URL."
    Stop-Process -Id $nodeProcess.Id -Force
    Stop-Process -Id $tunnelProcess.Id -Force
    exit 1
}

Write-Host "`nTunnel Established: $tunnelUrl" -ForegroundColor Green
# ========================================================

# ================= GITHUB UPDATE =========================
Write-Host "Updating GitHub ($GithubRepo)..." -ForegroundColor Cyan

$repoParts = $GithubRepo.Split("/")
$owner = $repoParts[0]
$repo = $repoParts[1]
$path = $GithubFile

$headers = @{
    Authorization = "Bearer $env:GITHUB_TOKEN"
    Accept        = "application/vnd.github+json"
    "User-Agent"  = "server-player-automation"
}

try {
    # --- Build GET URI safely ---
    $getBuilder = New-Object System.UriBuilder
    $getBuilder.Scheme = "https"
    $getBuilder.Host = "api.github.com"
    $getBuilder.Path = "repos/$owner/$repo/contents/$path"
    $getBuilder.Query = "ref=$GithubBranch"
    $getUri = $getBuilder.Uri

    $fileInfo = Invoke-RestMethod -Uri $getUri -Headers $headers -Method Get
    $sha = $fileInfo.sha

    # --- Prepare new content ---
    $contentObj = @{
        auth_server = $tunnelUrl
        updated_at  = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        status      = "online"
    }

    $jsonContent = $contentObj | ConvertTo-Json -Depth 5
    $encodedContent = [Convert]::ToBase64String(
        [Text.Encoding]::UTF8.GetBytes($jsonContent)
    )

    $body = @{
        message = "Update server endpoint to $tunnelUrl"
        content = $encodedContent
        sha     = $sha
        branch  = $GithubBranch
    } | ConvertTo-Json -Depth 5

    # --- Build PUT URI safely ---
    $putBuilder = New-Object System.UriBuilder
    $putBuilder.Scheme = "https"
    $putBuilder.Host = "api.github.com"
    $putBuilder.Path = "repos/$owner/$repo/contents/$path"
    $putUri = $putBuilder.Uri

    Invoke-RestMethod -Uri $putUri -Headers $headers -Method Put -Body $body
    Write-Host "GitHub Updated Successfully!" -ForegroundColor Green
}
catch {
    Write-Error "GitHub Update Failed: $($_.Exception.Message)"
}
# ========================================================

# ================= WAIT LOOP =============================
Write-Host "`n--------------------------------------------------" -ForegroundColor Yellow
Write-Host " Service Running. Press ENTER to Stop." -ForegroundColor Yellow
Write-Host "--------------------------------------------------" -ForegroundColor Yellow

if ($env:CI_MODE) {
    Write-Host "Service Running in CI Mode. Loop forever..." -ForegroundColor Yellow
    while ($true) { Start-Sleep 60 }
}
else {
    Read-Host
}
# ========================================================

# ================= CLEANUP ===============================
Write-Host "Stopping services..." -ForegroundColor Cyan
Stop-Process -Id $nodeProcess.Id -ErrorAction SilentlyContinue
Stop-Process -Id $tunnelProcess.Id -ErrorAction SilentlyContinue
Write-Host "Stopped." -ForegroundColor Green
# ========================================================
