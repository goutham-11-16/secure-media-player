# Server Automation Setup

This guide explains how to use the `start.ps1` script to automate your server startup, tunneling, and GitHub updates.

## Prerequisites

1.  **Cloudflared**:
    - Download and install [Cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/) for Windows.
    - Ensure `cloudflared.exe` is in your System PATH (you should be able to type `cloudflared` in PowerShell and see help output).

2.  **GitHub Token**:
    - Create a [Personal Access Token (Classic)](https://github.com/settings/tokens).
    - Scopes: `repo` (Full control of private repositories) or `public_repo` (if public).
    - **Security**: Do not share this token.

## Configuration

You need to set the `GITHUB_TOKEN` environment variable on your machine.

**Option A: Temporary (Current Session Only)**
```powershell
$env:GITHUB_TOKEN = "your_github_token_here"
```

**Option B: Permanent (User Variable)**
1.  Search Windows for "Edit environment variables for your account".
2.  Click **New** under "User variables".
3.  **Variable name**: `GITHUB_TOKEN`
4.  **Variable value**: `your_github_token_here`
5.  Restart PowerShell for it to take effect.

## Usage

1.  Open PowerShell in this directory (`backend`).
2.  Run the script:
    ```powershell
    .\start.ps1
    ```
3.  Enter your **Video Password** when prompted (input will be hidden).
4.  The script will:
    - Start `server.js`
    - Start `cloudflared` tunnel
    - Update `server_endpoint.json` on GitHub
    - Display "Service Running"

5.  **Stop**: Press `ENTER` in the PowerShell window to shut down the server and tunnel.

## Troubleshooting

- **Logs**: Check `server.log`, `server_err.log`, and `tunnel.log` in this directory if something goes wrong.
- **GitHub Error**: Ensure your token has write access to the `goutham-11-16/tv` repository.
