# Fresh-machine setup on Windows. Idempotent — safe to re-run.
# Run from an *elevated* PowerShell (choco and the config symlink need it):
#   Set-ExecutionPolicy Bypass -Scope Process -Force; .\bootstrap.ps1
# Installs the core tools via Chocolatey, links the nvim config, then hands
# over to `nvim --headless "+Doctor sync"` — the same dependency registry the
# in-editor Doctor panel uses (util/doctor/registry.lua).
$ErrorActionPreference = "Continue"
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigDir = Join-Path $env:LOCALAPPDATA "nvim"
# llvm brings clangd (and clang-format) for the C/C++ layer; mingw is what
# actually compiles, and clangd is configured to follow it (util/clangd_config.lua).
$CoreTools = @("neovim", "git", "ripgrep", "fd", "nodejs-lts", "mingw", "llvm")

function Say($msg) { Write-Host "==> $msg" -ForegroundColor Blue }
function Warn($msg) { Write-Host "warning: $msg" -ForegroundColor Yellow }

# ── chocolatey + core tools ─────────────────────────────────────────────
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Say "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Warn "Chocolatey install failed — is this shell elevated? Install it manually, then re-run."
        exit 1
    }
}
Say "choco install $($CoreTools -join ' ')"
choco install -y @CoreTools
if ($LASTEXITCODE -ne 0) { Warn "choco reported errors — Doctor will show what's still missing" }

# ── config symlink ───────────────────────────────────────────────────────
$Target = Join-Path $Repo "nvim"
if (Test-Path $ConfigDir) {
    $existing = Get-Item $ConfigDir -Force
    if ($existing.LinkType -and $existing.Target -eq $Target) {
        Say "symlink already in place: $ConfigDir -> $Target"
    } else {
        $Backup = "$ConfigDir.backup.$([DateTimeOffset]::Now.ToUnixTimeSeconds())"
        Say "existing $ConfigDir moved to $Backup"
        Move-Item $ConfigDir $Backup
        New-Item -ItemType SymbolicLink -Path $ConfigDir -Target $Target | Out-Null
    }
} else {
    Say "linking $ConfigDir -> $Target"
    New-Item -ItemType SymbolicLink -Path $ConfigDir -Target $Target | Out-Null
}

# ── editor layer (plugins, parsers, LSP servers) ────────────────────────
# refresh PATH so the just-installed nvim is visible in this shell
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
    [System.Environment]::GetEnvironmentVariable("Path", "User")
if (Get-Command nvim -ErrorAction SilentlyContinue) {
    Say "running nvim --headless '+Doctor sync' (first run also bootstraps lazy.nvim — this can take a few minutes)..."
    nvim --headless "+Doctor sync" "+qa"
    if ($LASTEXITCODE -ne 0) { Warn "Doctor sync reported problems — open nvim and check the Doctor panel" }
} else {
    Warn "nvim not on PATH — open a new shell and run: nvim --headless `"+Doctor sync`""
}

Say "done. Open nvim and press <leader><space> -> Doctor to see the full status."
