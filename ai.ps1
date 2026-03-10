param(
    [Parameter(Position = 0)]
    [string]$Tool,
    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$ExtraArgs
)

function Get-WingetVersion($PackageId) {
    $lines = winget list --id $PackageId --disable-interactivity 2>$null
    foreach ($line in $lines) {
        if ($line -match $PackageId) {
            if ($line -match '(\d+\.\d+[\.\d]*)') { return $Matches[1] }
        }
    }
    return $null
}

function Update-WingetPackage($DisplayName, $PackageId) {
    Write-Host "==> Checking $DisplayName..." -ForegroundColor Cyan
    $ver = Get-WingetVersion $PackageId
    if (-not $ver) {
        Write-Host "  Not installed via winget" -ForegroundColor Yellow
        return
    }
    $output = winget upgrade $PackageId --disable-interactivity 2>&1 | Out-String
    if ($output -match "No available upgrade found|No newer package") {
        Write-Host "  Already up to date ($ver)" -ForegroundColor Green
    } else {
        $newVer = Get-WingetVersion $PackageId
        if ($newVer) {
            Write-Host "  Updated $ver -> $newVer" -ForegroundColor Yellow
        } else {
            Write-Host "  Updated successfully" -ForegroundColor Yellow
        }
    }
}

function Update-GhCopilot {
    Write-Host "==> Checking GitHub Copilot CLI..." -ForegroundColor Cyan
    $output = gh copilot update 2>&1 | Out-String
    if ($output -match "No update needed.*current version is ([^\s,]+)") {
        Write-Host "  Already up to date ($($Matches[1]))" -ForegroundColor Green
    } elseif ($output -match "Updated|updated|Updating") {
        Write-Host "  Updated successfully" -ForegroundColor Yellow
    } else {
        Write-Host "  Already up to date" -ForegroundColor Green
    }
}

function Update-NpmPackage($DisplayName, $Package) {
    Write-Host "==> Checking $DisplayName..." -ForegroundColor Cyan
    $current = (npm list -g $Package --depth=0 --json 2>$null | ConvertFrom-Json).dependencies.$Package.version
    $latest  = (npm view $Package version 2>$null).Trim()
    if (-not $current) {
        Write-Host "  Not installed, installing $latest..." -ForegroundColor Yellow
        npm install -g "${Package}@latest" --loglevel error
    } elseif ($current -eq $latest) {
        Write-Host "  Already up to date ($current)" -ForegroundColor Green
    } else {
        Write-Host "  Updating $current -> $latest..." -ForegroundColor Yellow
        npm install -g "${Package}@latest" --loglevel error
    }
}

switch ($Tool) {
    "claude"  { claude --dangerously-skip-permissions @ExtraArgs }
    "codex"   { codex --yolo @ExtraArgs }
    "gemini"  { gemini --yolo @ExtraArgs }
    "copilot" { gh copilot --yolo @ExtraArgs }
    "update"  {
        Update-WingetPackage "Claude Code" "Anthropic.ClaudeCode"
        Write-Host ""
        Update-WingetPackage "GitHub CLI" "GitHub.cli"
        Write-Host ""
        Update-GhCopilot
        Write-Host ""
        Update-NpmPackage "Gemini CLI" "@google/gemini-cli"
        Write-Host ""
        Update-NpmPackage "Codex CLI" "@openai/codex"
        Write-Host ""
        Update-NpmPackage "OpenCode" "opencode-ai"
        Write-Host ""
        Write-Host "All AI tools checked." -ForegroundColor Green
    }
    default {
        Write-Host "Usage: ai <tool> [extra args]"
        Write-Host "  ai claude   -> claude --dangerously-skip-permissions"
        Write-Host "  ai codex    -> codex --yolo"
        Write-Host "  ai gemini   -> gemini --yolo"
        Write-Host "  ai copilot  -> gh copilot --yolo"
        Write-Host "  ai update   -> update all AI tools"
    }
}
