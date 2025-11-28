#!/usr/bin/env pwsh
# Create a new spec (feature, fix, chore, etc.)
[CmdletBinding()]
param(
    [switch]$Json,
    [string]$ShortName,
    [int]$Number = 0,
    [switch]$Help,
    [switch]$Interactive,
    [ValidateSet('feature', 'fix', 'chore', 'docs', 'refactor', 'test', 'style', 'perf')]
    [string]$Type,
    [string]$Purpose,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FeatureDescription
)
$ErrorActionPreference = 'Stop'

# Show help if requested
if ($Help) {
    Write-Host "Usage: ./create-new-feature.ps1 [-Json] [-ShortName <name>] [-Number N] [-Type <type>] [-Purpose <purpose>] [-Interactive] <description>"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Json               Output in JSON format"
    Write-Host "  -ShortName <name>   Provide a custom short name (2-4 words) for the branch"
    Write-Host "  -Number N           Specify branch number manually (overrides auto-detection)"
    Write-Host "  -Type <type>        Branch type: feature, fix, chore, docs, refactor, test, style, perf"
    Write-Host "  -Purpose <purpose>  Brief description of what this spec is for"
    Write-Host "  -Interactive        Run in interactive mode with prompts"
    Write-Host "  -Help               Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  ./create-new-feature.ps1 -Interactive"
    Write-Host "  ./create-new-feature.ps1 -Type feature -Purpose 'Add login flow' 'user-auth'"
    Write-Host "  ./create-new-feature.ps1 -Type fix 'Fix login timeout issue'"
    exit 0
}

# Branch type descriptions for interactive mode
$typeDescriptions = @{
    'feature'  = 'New feature or enhancement'
    'fix'      = 'Bug fix or error correction'
    'chore'    = 'Maintenance tasks, dependencies, configs'
    'docs'     = 'Documentation only changes'
    'refactor' = 'Code refactoring without behavior change'
    'test'     = 'Adding or updating tests'
    'style'    = 'Code style, formatting changes'
    'perf'     = 'Performance improvements'
}

# Always run interactive prompts at the beginning for missing required info
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                     Create New Spec                          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Step 1: Always ask for type first if not provided
if (-not $Type) {
    Write-Host "Step 1: What type of branch is this?" -ForegroundColor Yellow
    Write-Host ""
    $typeOptions = @('feature', 'fix', 'chore', 'docs', 'refactor', 'test', 'style', 'perf')
    for ($i = 0; $i -lt $typeOptions.Count; $i++) {
        $t = $typeOptions[$i]
        Write-Host "  [$($i + 1)] " -NoNewline -ForegroundColor Green
        Write-Host "$t" -NoNewline -ForegroundColor White
        Write-Host " - $($typeDescriptions[$t])" -ForegroundColor Gray
    }
    Write-Host ""
    
    do {
        $selection = Read-Host "Enter your choice (1-8)"
        $selNum = 0
        $validSelection = [int]::TryParse($selection, [ref]$selNum) -and $selNum -ge 1 -and $selNum -le 8
        if (-not $validSelection) {
            Write-Host "Invalid selection. Please enter a number between 1 and 8." -ForegroundColor Red
        }
    } while (-not $validSelection)
    
    $Type = $typeOptions[$selNum - 1]
    Write-Host ""
    Write-Host "  ✓ Selected: $Type" -ForegroundColor Green
} else {
    Write-Host "Step 1: Branch type" -ForegroundColor Yellow
    Write-Host "  ✓ Using: $Type" -ForegroundColor Green
}

# Step 2: Always ask for purpose/requirements if not provided
if (-not $Purpose -and (-not $FeatureDescription -or $FeatureDescription.Count -eq 0)) {
    Write-Host ""
    Write-Host "Step 2: What is this spec for? (Brief description of the goal/requirement)" -ForegroundColor Yellow
    Write-Host "        Example: 'Add user authentication with OAuth2 support'" -ForegroundColor Gray
    Write-Host ""
    
    do {
        $Purpose = Read-Host "Purpose"
        if ([string]::IsNullOrWhiteSpace($Purpose)) {
            Write-Host "Purpose cannot be empty. Please provide a description." -ForegroundColor Red
        }
    } while ([string]::IsNullOrWhiteSpace($Purpose))
    
    Write-Host ""
    Write-Host "  ✓ Purpose set" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Step 2: Purpose/Requirements" -ForegroundColor Yellow
    $displayPurpose = if ($Purpose) { $Purpose } else { ($FeatureDescription -join ' ').Trim() }
    Write-Host "  ✓ Using: $displayPurpose" -ForegroundColor Green
}

# Step 3: Ask for short name if not provided
if (-not $ShortName) {
    Write-Host ""
    Write-Host "Step 3: Provide a short name for the branch (2-4 words)" -ForegroundColor Yellow
    Write-Host "        Press Enter to auto-generate from purpose" -ForegroundColor Gray
    Write-Host "        Example: 'user-auth', 'login-fix', 'deps-update'" -ForegroundColor Gray
    Write-Host ""
    
    $shortNameInput = Read-Host "Short name (optional)"
    if (-not [string]::IsNullOrWhiteSpace($shortNameInput)) {
        $ShortName = $shortNameInput
        Write-Host ""
        Write-Host "  ✓ Short name: $ShortName" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "  ✓ Will auto-generate from purpose" -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "Step 3: Short name" -ForegroundColor Yellow
    Write-Host "  ✓ Using: $ShortName" -ForegroundColor Green
}

Write-Host ""
Write-Host "────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Build feature description from purpose or remaining arguments
if ($Purpose) {
    $featureDesc = $Purpose
} elseif ($FeatureDescription -and $FeatureDescription.Count -gt 0) {
    $featureDesc = ($FeatureDescription -join ' ').Trim()
} else {
    Write-Error "Description is required. This should not happen - please report this bug."
    exit 1
}

# Resolve repository root. Prefer git information when available, but fall back
# to searching for repository markers so the workflow still functions in repositories that
# were initialized with --no-git.
function Find-RepositoryRoot {
    param(
        [string]$StartDir,
        [string[]]$Markers = @('.git', '.specify')
    )
    $current = Resolve-Path $StartDir
    while ($true) {
        foreach ($marker in $Markers) {
            if (Test-Path (Join-Path $current $marker)) {
                return $current
            }
        }
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) {
            # Reached filesystem root without finding markers
            return $null
        }
        $current = $parent
    }
}

function Get-HighestNumberFromSpecs {
    param([string]$SpecsDir)
    
    $highest = 0
    if (Test-Path $SpecsDir) {
        Get-ChildItem -Path $SpecsDir -Directory | ForEach-Object {
            if ($_.Name -match '^(\d+)') {
                $num = [int]$matches[1]
                if ($num -gt $highest) { $highest = $num }
            }
        }
    }
    return $highest
}

function Get-HighestNumberFromBranches {
    param()
    
    $highest = 0
    try {
        $branches = git branch -a 2>$null
        if ($LASTEXITCODE -eq 0) {
            foreach ($branch in $branches) {
                # Clean branch name: remove leading markers and remote prefixes
                $cleanBranch = $branch.Trim() -replace '^\*?\s+', '' -replace '^remotes/[^/]+/', ''
                
                # Extract feature number if branch matches pattern ###-*
                if ($cleanBranch -match '^(\d+)-') {
                    $num = [int]$matches[1]
                    if ($num -gt $highest) { $highest = $num }
                }
            }
        }
    } catch {
        # If git command fails, return 0
        Write-Verbose "Could not check Git branches: $_"
    }
    return $highest
}

function Get-NextBranchNumber {
    param(
        [string]$ShortName,
        [string]$SpecsDir
    )
    
    # Fetch all remotes to get latest branch info (suppress errors if no remotes)
    try {
        git fetch --all --prune 2>$null | Out-Null
    } catch {
        # Ignore fetch errors
    }
    
    # Find remote branches matching the pattern using git ls-remote
    $remoteBranches = @()
    try {
        $remoteRefs = git ls-remote --heads origin 2>$null
        if ($remoteRefs) {
            $remoteBranches = $remoteRefs | Where-Object { $_ -match "refs/heads/(\d+)-$([regex]::Escape($ShortName))$" } | ForEach-Object {
                if ($_ -match "refs/heads/(\d+)-") {
                    [int]$matches[1]
                }
            }
        }
    } catch {
        # Ignore errors
    }
    
    # Check local branches
    $localBranches = @()
    try {
        $allBranches = git branch 2>$null
        if ($allBranches) {
            $localBranches = $allBranches | Where-Object { $_ -match "^\*?\s*(\d+)-$([regex]::Escape($ShortName))$" } | ForEach-Object {
                if ($_ -match "(\d+)-") {
                    [int]$matches[1]
                }
            }
        }
    } catch {
        # Ignore errors
    }
    
    # Check specs directory
    $specDirs = @()
    if (Test-Path $SpecsDir) {
        try {
            $specDirs = Get-ChildItem -Path $SpecsDir -Directory | Where-Object { $_.Name -match "^(\d+)-$([regex]::Escape($ShortName))$" } | ForEach-Object {
                if ($_.Name -match "^(\d+)-") {
                    [int]$matches[1]
                }
            }
        } catch {
            # Ignore errors
        }
    }
    
    # Combine all sources and get the highest number
    $maxNum = 0
    foreach ($num in ($remoteBranches + $localBranches + $specDirs)) {
        if ($num -gt $maxNum) {
            $maxNum = $num
        }
    }
    
    # Return next number
    return $maxNum + 1
}

function ConvertTo-CleanBranchName {
    param([string]$Name)
    
    return $Name.ToLower() -replace '[^a-z0-9]', '-' -replace '-{2,}', '-' -replace '^-', '' -replace '-$', ''
}
$fallbackRoot = (Find-RepositoryRoot -StartDir $PSScriptRoot)
if (-not $fallbackRoot) {
    Write-Error "Error: Could not determine repository root. Please run this script from within the repository."
    exit 1
}

try {
    $repoRoot = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0) {
        $hasGit = $true
    } else {
        throw "Git not available"
    }
} catch {
    $repoRoot = $fallbackRoot
    $hasGit = $false
}

Set-Location $repoRoot

$specsDir = Join-Path $repoRoot 'specs'
New-Item -ItemType Directory -Path $specsDir -Force | Out-Null

# Function to generate branch name with stop word filtering and length filtering
function Get-BranchName {
    param([string]$Description)
    
    # Common stop words to filter out
    $stopWords = @(
        'i', 'a', 'an', 'the', 'to', 'for', 'of', 'in', 'on', 'at', 'by', 'with', 'from',
        'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had',
        'do', 'does', 'did', 'will', 'would', 'should', 'could', 'can', 'may', 'might', 'must', 'shall',
        'this', 'that', 'these', 'those', 'my', 'your', 'our', 'their',
        'want', 'need', 'add', 'get', 'set'
    )
    
    # Convert to lowercase and extract words (alphanumeric only)
    $cleanName = $Description.ToLower() -replace '[^a-z0-9\s]', ' '
    $words = $cleanName -split '\s+' | Where-Object { $_ }
    
    # Filter words: remove stop words and words shorter than 3 chars (unless they're uppercase acronyms in original)
    $meaningfulWords = @()
    foreach ($word in $words) {
        # Skip stop words
        if ($stopWords -contains $word) { continue }
        
        # Keep words that are length >= 3 OR appear as uppercase in original (likely acronyms)
        if ($word.Length -ge 3) {
            $meaningfulWords += $word
        } elseif ($Description -match "\b$($word.ToUpper())\b") {
            # Keep short words if they appear as uppercase in original (likely acronyms)
            $meaningfulWords += $word
        }
    }
    
    # If we have meaningful words, use first 3-4 of them
    if ($meaningfulWords.Count -gt 0) {
        $maxWords = if ($meaningfulWords.Count -eq 4) { 4 } else { 3 }
        $result = ($meaningfulWords | Select-Object -First $maxWords) -join '-'
        return $result
    } else {
        # Fallback to original logic if no meaningful words found
        $result = ConvertTo-CleanBranchName -Name $Description
        $fallbackWords = ($result -split '-') | Where-Object { $_ } | Select-Object -First 3
        return [string]::Join('-', $fallbackWords)
    }
}

# Generate branch name suffix
if ($ShortName) {
    # Use provided short name, just clean it up
    $branchSuffix = ConvertTo-CleanBranchName -Name $ShortName
} else {
    # Generate from description with smart filtering
    $branchSuffix = Get-BranchName -Description $featureDesc
}

# Create the type-specific specs directory structure
$typeSpecsDir = Join-Path $specsDir $Type
New-Item -ItemType Directory -Path $typeSpecsDir -Force | Out-Null

# Determine branch number (search within the type-specific directory)
if ($Number -eq 0) {
    if ($hasGit) {
        # Check existing branches on remotes (with type prefix)
        $Number = Get-NextBranchNumber -ShortName "$Type/$branchSuffix" -SpecsDir $typeSpecsDir
    } else {
        # Fall back to local directory check within type folder
        $Number = (Get-HighestNumberFromSpecs -SpecsDir $typeSpecsDir) + 1
    }
}

$featureNum = ('{0:000}' -f $Number)
# Branch name format: type/###-short-name (e.g., feature/001-user-auth)
$branchName = "$Type/$featureNum-$branchSuffix"
# Folder name format: ###-short-name (within type folder)
$folderName = "$featureNum-$branchSuffix"

# GitHub enforces a 244-byte limit on branch names
# Validate and truncate if necessary
$maxBranchLength = 244
if ($branchName.Length -gt $maxBranchLength) {
    # Calculate how much we need to trim from suffix
    # Account for: type/ + feature number (3) + hyphen (1)
    $prefixLength = $Type.Length + 1 + 4  # type/ + ###-
    $maxSuffixLength = $maxBranchLength - $prefixLength
    
    # Truncate suffix
    $truncatedSuffix = $branchSuffix.Substring(0, [Math]::Min($branchSuffix.Length, $maxSuffixLength))
    # Remove trailing hyphen if truncation created one
    $truncatedSuffix = $truncatedSuffix -replace '-$', ''
    
    $originalBranchName = $branchName
    $branchName = "$Type/$featureNum-$truncatedSuffix"
    $folderName = "$featureNum-$truncatedSuffix"
    
    Write-Warning "[specify] Branch name exceeded GitHub's 244-byte limit"
    Write-Warning "[specify] Original: $originalBranchName ($($originalBranchName.Length) bytes)"
    Write-Warning "[specify] Truncated to: $branchName ($($branchName.Length) bytes)"
}

if ($hasGit) {
    try {
        git checkout -b $branchName | Out-Null
    } catch {
        Write-Warning "Failed to create git branch: $branchName"
    }
} else {
    Write-Warning "[specify] Warning: Git repository not detected; skipped branch creation for $branchName"
}

# Create folder under specs/<type>/<###-short-name>
$featureDir = Join-Path $typeSpecsDir $folderName
New-Item -ItemType Directory -Path $featureDir -Force | Out-Null

$template = Join-Path $repoRoot '.specify/templates/spec-template.md'
$specFile = Join-Path $featureDir 'spec.md'
if (Test-Path $template) { 
    # Read template and replace placeholders
    $templateContent = Get-Content $template -Raw
    $templateContent = $templateContent -replace '\[FEATURE NAME\]', $featureDesc
    $templateContent = $templateContent -replace '\[###-feature-name\]', $branchName
    $templateContent = $templateContent -replace '\[DATE\]', (Get-Date -Format 'yyyy-MM-dd')
    $templateContent = $templateContent -replace '\$ARGUMENTS', $featureDesc
    
    # Add type and purpose metadata
    $typeHeader = "**Type**: ``$Type``  `n"
    $templateContent = $templateContent -replace '(\*\*Feature Branch\*\*:)', "$typeHeader`$1"
    
    Set-Content -Path $specFile -Value $templateContent
} else { 
    New-Item -ItemType File -Path $specFile | Out-Null 
}

# Set the SPECIFY_FEATURE environment variable for the current session
$env:SPECIFY_FEATURE = $branchName

if ($Json) {
    $obj = [PSCustomObject]@{ 
        BRANCH_NAME = $branchName
        BRANCH_TYPE = $Type
        SPEC_FILE = $specFile
        FEATURE_DIR = $featureDir
        FEATURE_NUM = $featureNum
        PURPOSE = $featureDesc
        HAS_GIT = $hasGit
    }
    $obj | ConvertTo-Json -Compress
} else {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                    Spec Created Successfully                 ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Type:        " -NoNewline -ForegroundColor Cyan
    Write-Host $Type -ForegroundColor White
    Write-Host "  Branch:      " -NoNewline -ForegroundColor Cyan
    Write-Host $branchName -ForegroundColor White
    Write-Host "  Folder:      " -NoNewline -ForegroundColor Cyan
    Write-Host "specs/$Type/$folderName" -ForegroundColor White
    Write-Host "  Spec File:   " -NoNewline -ForegroundColor Cyan
    Write-Host $specFile -ForegroundColor White
    Write-Host "  Purpose:     " -NoNewline -ForegroundColor Cyan
    Write-Host $featureDesc -ForegroundColor White
    Write-Host ""
    Write-Host "  SPECIFY_FEATURE environment variable set to: $branchName" -ForegroundColor DarkGray
    Write-Host ""
}

