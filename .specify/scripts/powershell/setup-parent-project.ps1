#!/usr/bin/env pwsh
# Setup script for parent projects using Specify as a submodule
# This script initializes the parent project's .specify-local directory
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Help
)
$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host "Usage: ./setup-parent-project.ps1 [-Force] [-Help]"
    Write-Host ""
    Write-Host "This script sets up the parent project to use Specify as a submodule."
    Write-Host "It creates the .specify-local directory with project-specific configuration."
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Force    Overwrite existing files"
    Write-Host "  -Help     Show this help message"
    Write-Host ""
    Write-Host "Run this from the Specify submodule directory."
    exit 0
}

# Find the submodule root (where this script lives)
$submoduleRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path

# Find the parent project root (one level up from submodule)
$parentRoot = (Resolve-Path (Join-Path $submoduleRoot "..")).Path

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              Specify - Parent Project Setup                  ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Submodule:     $submoduleRoot" -ForegroundColor Gray
Write-Host "  Parent Project: $parentRoot" -ForegroundColor Gray
Write-Host ""

# Create .specify-local directory in parent project
$specifyLocalDir = Join-Path $parentRoot ".specify-local"
$constitutionFile = Join-Path $specifyLocalDir "constitution.md"
$templateFile = Join-Path $submoduleRoot ".specify/memory/constitution-template.md"

# Create directory
if (-not (Test-Path $specifyLocalDir)) {
    New-Item -ItemType Directory -Path $specifyLocalDir -Force | Out-Null
    Write-Host "  ✓ Created .specify-local directory" -ForegroundColor Green
} else {
    Write-Host "  • .specify-local directory already exists" -ForegroundColor Yellow
}

# Copy constitution template
if (-not (Test-Path $constitutionFile) -or $Force) {
    if (Test-Path $templateFile) {
        Copy-Item $templateFile $constitutionFile -Force
        Write-Host "  ✓ Created constitution.md from template" -ForegroundColor Green
        Write-Host "    → Please customize this file for your project!" -ForegroundColor Yellow
    } else {
        Write-Warning "Template file not found: $templateFile"
    }
} else {
    Write-Host "  • constitution.md already exists (use -Force to overwrite)" -ForegroundColor Yellow
}

# Create specs directory in parent project
$specsDir = Join-Path $parentRoot "specs"
if (-not (Test-Path $specsDir)) {
    New-Item -ItemType Directory -Path $specsDir -Force | Out-Null
    Write-Host "  ✓ Created specs directory" -ForegroundColor Green
} else {
    Write-Host "  • specs directory already exists" -ForegroundColor Yellow
}

# Create .gitignore for .specify-local if needed (to not ignore it)
$gitignoreFile = Join-Path $specifyLocalDir ".gitignore"
if (-not (Test-Path $gitignoreFile)) {
    Set-Content -Path $gitignoreFile -Value "# Keep this directory in version control`n"
    Write-Host "  ✓ Created .specify-local/.gitignore" -ForegroundColor Green
}

Write-Host ""
Write-Host "────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "  1. Edit .specify-local/constitution.md with your project's rules"
Write-Host "  2. Run specs using: ./Specify/.specify/scripts/powershell/create-new-feature.ps1"
Write-Host ""
