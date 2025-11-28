#!/usr/bin/env pwsh
# Common PowerShell functions analogous to common.sh

# Get the Specify submodule root (where this toolkit lives)
function Get-SpecifyRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
}

# Get the parent project root (the project using Specify as submodule)
# Falls back to Specify root if not used as submodule
function Get-ParentProjectRoot {
    $specifyRoot = Get-SpecifyRoot
    $potentialParent = (Resolve-Path (Join-Path $specifyRoot "..") -ErrorAction SilentlyContinue).Path
    
    # Check if we're actually a submodule by looking for common project indicators
    if ($potentialParent -and (
        (Test-Path (Join-Path $potentialParent ".git")) -or
        (Test-Path (Join-Path $potentialParent ".specify-local")) -or
        (Test-Path (Join-Path $potentialParent "specs"))
    )) {
        return $potentialParent
    }
    
    # Not a submodule, return Specify root
    return $specifyRoot
}

# Get the constitution file path
# Priority: 1. Parent's .specify-local/constitution.md
#           2. Specify's template (as fallback)
function Get-ConstitutionPath {
    $parentRoot = Get-ParentProjectRoot
    $specifyRoot = Get-SpecifyRoot
    
    # First check parent project's local constitution
    $parentConstitution = Join-Path $parentRoot ".specify-local/constitution.md"
    if (Test-Path $parentConstitution) {
        return @{
            Path = $parentConstitution
            IsTemplate = $false
            Source = "project"
        }
    }
    
    # Fall back to template
    $templateConstitution = Join-Path $specifyRoot ".specify/memory/constitution-template.md"
    if (Test-Path $templateConstitution) {
        return @{
            Path = $templateConstitution
            IsTemplate = $true
            Source = "template"
        }
    }
    
    return $null
}

# Get the specs directory (in parent project if submodule, otherwise in Specify root)
function Get-SpecsDir {
    $parentRoot = Get-ParentProjectRoot
    return Join-Path $parentRoot "specs"
}

function Get-RepoRoot {
    # When used as submodule, return parent project root
    # This maintains backward compatibility
    $parentRoot = Get-ParentProjectRoot
    
    try {
        $result = git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $result
        }
    } catch {
        # Git command failed
    }
    
    return $parentRoot
}

function Get-CurrentBranch {
    # First check if SPECIFY_FEATURE environment variable is set
    if ($env:SPECIFY_FEATURE) {
        return $env:SPECIFY_FEATURE
    }
    
    # Then check git if available
    try {
        $result = git rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $result
        }
    } catch {
        # Git command failed
    }
    
    # For non-git repos, try to find the latest feature directory
    $repoRoot = Get-RepoRoot
    $specsDir = Join-Path $repoRoot "specs"
    
    if (Test-Path $specsDir) {
        $latestFeature = ""
        $highest = 0
        $latestType = ""
        
        # Check type subdirectories first (new pattern)
        $validTypes = @('feature', 'fix', 'chore', 'docs', 'refactor', 'test', 'style', 'perf')
        foreach ($type in $validTypes) {
            $typeDir = Join-Path $specsDir $type
            if (Test-Path $typeDir) {
                Get-ChildItem -Path $typeDir -Directory | ForEach-Object {
                    if ($_.Name -match '^(\d{3})-') {
                        $num = [int]$matches[1]
                        if ($num -gt $highest) {
                            $highest = $num
                            $latestFeature = $_.Name
                            $latestType = $type
                        }
                    }
                }
            }
        }
        
        # Also check direct children (old pattern)
        Get-ChildItem -Path $specsDir -Directory | ForEach-Object {
            if ($_.Name -match '^(\d{3})-') {
                $num = [int]$matches[1]
                if ($num -gt $highest) {
                    $highest = $num
                    $latestFeature = $_.Name
                    $latestType = ""
                }
            }
        }
        
        if ($latestFeature) {
            if ($latestType) {
                return "$latestType/$latestFeature"
            }
            return $latestFeature
        }
    }
    
    # Final fallback
    return "main"
}

function Test-HasGit {
    try {
        git rev-parse --show-toplevel 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Test-FeatureBranch {
    param(
        [string]$Branch,
        [bool]$HasGit = $true
    )
    
    # For non-git repos, we can't enforce branch naming but still provide output
    if (-not $HasGit) {
        Write-Warning "[specify] Warning: Git repository not detected; skipped branch validation"
        return $true
    }
    
    # Support both old pattern (###-name) and new pattern (type/###-name)
    $validTypes = @('feature', 'fix', 'chore', 'docs', 'refactor', 'test', 'style', 'perf')
    $typePattern = ($validTypes -join '|')
    
    if ($Branch -notmatch "^($typePattern)/[0-9]{3}-" -and $Branch -notmatch '^[0-9]{3}-') {
        Write-Output "ERROR: Not on a valid spec branch. Current branch: $Branch"
        Write-Output "Spec branches should be named like: feature/001-feature-name or 001-feature-name"
        Write-Output "Valid types: $($validTypes -join ', ')"
        return $false
    }
    return $true
}

function Get-FeatureDir {
    param([string]$RepoRoot, [string]$Branch)
    
    # Check if branch follows new pattern: type/###-name
    $validTypes = @('feature', 'fix', 'chore', 'docs', 'refactor', 'test', 'style', 'perf')
    $typePattern = ($validTypes -join '|')
    
    if ($Branch -match "^($typePattern)/(\d{3}-.+)$") {
        $type = $matches[1]
        $folderName = $matches[2]
        return Join-Path $RepoRoot "specs/$type/$folderName"
    }
    
    # Fall back to old pattern: ###-name (directly under specs/)
    return Join-Path $RepoRoot "specs/$Branch"
}

function Get-FeaturePathsEnv {
    $repoRoot = Get-RepoRoot
    $currentBranch = Get-CurrentBranch
    $hasGit = Test-HasGit
    $featureDir = Get-FeatureDir -RepoRoot $repoRoot -Branch $currentBranch
    
    [PSCustomObject]@{
        REPO_ROOT     = $repoRoot
        CURRENT_BRANCH = $currentBranch
        HAS_GIT       = $hasGit
        FEATURE_DIR   = $featureDir
        FEATURE_SPEC  = Join-Path $featureDir 'spec.md'
        IMPL_PLAN     = Join-Path $featureDir 'plan.md'
        TASKS         = Join-Path $featureDir 'tasks.md'
        RESEARCH      = Join-Path $featureDir 'research.md'
        DATA_MODEL    = Join-Path $featureDir 'data-model.md'
        QUICKSTART    = Join-Path $featureDir 'quickstart.md'
        CONTRACTS_DIR = Join-Path $featureDir 'contracts'
    }
}

function Test-FileExists {
    param([string]$Path, [string]$Description)
    if (Test-Path -Path $Path -PathType Leaf) {
        Write-Output "  ✓ $Description"
        return $true
    } else {
        Write-Output "  ✗ $Description"
        return $false
    }
}

function Test-DirHasFiles {
    param([string]$Path, [string]$Description)
    if ((Test-Path -Path $Path -PathType Container) -and (Get-ChildItem -Path $Path -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Select-Object -First 1)) {
        Write-Output "  ✓ $Description"
        return $true
    } else {
        Write-Output "  ✗ $Description"
        return $false
    }
}

