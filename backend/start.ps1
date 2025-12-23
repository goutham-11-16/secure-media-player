<#
.SYNOPSIS
    Automated Server Startup Script
.DESCRIPTION
    Starts Node server, Cloudflare tunnel,
    optionally updates GitHub endpoint.
.NOTES
    Requires node & cloudflared in PATH.
    GitHub update is OPTIONAL.
#>

param()

# ===================== CONFIG =====================
$GithubRepo = "goutham-11-16/tv"
$GithubBranch = "main"
$GithubFile = "server_endpoint.json"
$LocalPort = 3000
# ================================================

# ===================== CHECKS =====================
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js not found in PATH."
    exit 1
}

if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
    Write-Error "cloudflared not found in PATH."
    exit 1
}

$githubEnabled = $true
if (-not $env:GITHUB_TOKEN) {
    Write-Warning "GITHUB_TOKEN missing → GitHub update will be skipped."
    $githubEnabled = $false
}
# ================================================

# ================= PASSWORD INPUT =================
Write-Host "Enter Video Encryption Password (Hidden): " -NoNewline -ForegroundColor Cyan
$securePass = Read-Host -AsSecureString
$videoPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
)
Write-Host "`nPassword captured." -ForegroundColor Green
$env:VIDEO_PASSWORD = $videoPassword
# ================================================

# ================= START SERVER ===================
Write-Host "Starting Auth Server on Port $LocalPort..." -ForegroundColor Cyan

$nodeProcess = Start-Process `
    -FilePath node `
    -ArgumentList "server.js" `
    -PassThru `
    -NoNewWindow `
    -RedirectStandardOutput "server.log" `
    -RedirectStandardError "server_err.log"

Write-Host "Server started (PID: $($nodeProcess.Id))" -ForegroundColor Green
# ================================================

# ================= START TUNNEL ===================
Write-Host "Starting Cloudflare Tunnel..." -ForegroundColor Cyan

$tunnelLog = "tunnel.log"

# SAFE truncate instead of delete
"" | Out-File $tunnelLog -Encoding ascii -Force

$tunnelProcess = Start-Process `
    -FilePath cloudflared `
    -ArgumentList "tunnel --url http://localhost:$LocalPort" `
    -PassThru `
    -NoNewWindow `
    -RedirectStandardOutput "tunnel_stdout.log" `
    -RedirectStandardError $tunnelLog
# ================================================

# ================= GET TUNNEL URL =================
Write-Host "Waiting for Tunnel URL..." -NoNewline
$tunnelUrl = $null

for ($i = 0; $i -lt 30; $i++) {
    $log = Get-Content $tunnelLog -Raw -ErrorAction SilentlyContinue
    if ($log -match "https://[a-zA-Z0-9-]+\.trycloudflare\.com") {
        $tunnelUrl = $matches[0]
        break
    }
    Start-Sleep 1
    Write-Host "." -NoNewline
}

if (-not $tunnelUrl) {
    Write-Error "`nFailed to capture tunnel URL."
    goto CLEANUP
}

Write-Host "`nTunnel Established: $tunnelUrl" -ForegroundColor Green
# ================================================

# ================= GITHUB UPDATE ==================
if ($githubEnabled) {
    Write-Host "Updating GitHub endpoint..." -ForegroundColor Cyan

    try {
        $repoParts = $GithubRepo.Split("/")
        $owner = $repoParts[0]
        $repo = $repoParts[1]

        $headers = @{
            Authorization = "Bearer $env:GITHUB_TOKEN"
            Accept        = "application/vnd.github+json"
            "User-Agent"  = "secure-media-player"
        }

        # ---- BUILD GET URI (SAFE) ----
        $getBuilder = New-Object System.UriBuilder
        $getBuilder.Scheme = "https"
        $getBuilder.Host = "api.github.com"
        $getBuilder.Path = "repos/$owner/$repo/contents/$GithubFile"
        $getBuilder.Query = "ref=$GithubBranch"
        $getUri = $getBuilder.Uri

        $existing = Invoke-RestMethod -Uri $getUri -Headers $headers -Method Get
        $sha = $existing.sha

        # ---- BUILD CONTENT ----
        $payload = @{
            auth_server = $tunnelUrl
            updated_at  = (Get-Date).ToString("o")
            status      = "online"
        }

        $body = @{
            message = "Update server endpoint"
            content = [Convert]::ToBase64String(
                [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 5))
            )
            sha     = $sha
            branch  = $GithubBranch
        } | ConvertTo-Json -Depth 5

        # ---- BUILD PUT URI (SAFE) ----
        $putBuilder = New-Object System.UriBuilder
        $putBuilder.Scheme = "https"
        $putBuilder.Host = "api.github.com"
        $putBuilder.Path = "repos/$owner/$repo/contents/$GithubFile"
        $putUri = $putBuilder.Uri

        Invoke-RestMethod -Method Put -Uri $putUri -Headers $headers -Body $body

        Write-Host "GitHub updated successfully." -ForegroundColor Green
    }
    catch {
        Write-Warning "GitHub update skipped: $($_.Exception.Message)"
    }
}
# ================================================

Write-Host "`nService running. Press ENTER to stop." -ForegroundColor Yellow
Read-Host

:CLEANUP
Write-Host "Stopping services..." -ForegroundColor Cyan
Stop-Process -Id $nodeProcess.Id -ErrorAction SilentlyContinue
Stop-Process -Id $tunnelProcess.Id -ErrorAction SilentlyContinue
Write-Host "Stopped." -ForegroundColor Green
