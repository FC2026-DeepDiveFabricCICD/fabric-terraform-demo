# Initialize Azure DevOps Repository Remotely via REST API
# No local git clone required - pushes directly to Azure DevOps

param(
    [Parameter(Mandatory=$false)]
    [string]$TfVarsPath,
    
    [Parameter(Mandatory=$false)]
    [string]$PAT = $env:AZURE_DEVOPS_PAT
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Azure DevOps Remote Repo Initializer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Function to parse terraform.tfvars
function Get-TfVarsValue {
    param([string]$Content, [string]$Key)
    
    # Match key = "value" or key = 'value'
    if ($Content -match "(?m)^\s*$Key\s*=\s*[`"']([^`"']+)[`"']") {
        return $matches[1]
    }
    return $null
}

# Find and parse terraform.tfvars
$tfvarsFile = if ($TfVarsPath) { 
    $TfVarsPath 
} else { 
    Join-Path $PSScriptRoot "..\terraform.tfvars" 
}

if (-not (Test-Path $tfvarsFile)) {
    Write-Error "terraform.tfvars not found at: $tfvarsFile`nRun 'terraform apply' first or specify path with -TfVarsPath"
}

Write-Host "`nReading configuration from: $tfvarsFile" -ForegroundColor Yellow
$tfvarsContent = Get-Content $tfvarsFile -Raw

$OrgName = Get-TfVarsValue -Content $tfvarsContent -Key "azuredevops_org_name"
$ProjectName = Get-TfVarsValue -Content $tfvarsContent -Key "azuredevops_project_name"
$RepoName = Get-TfVarsValue -Content $tfvarsContent -Key "azuredevops_repository_name"

if (-not $OrgName) { Write-Error "azuredevops_org_name not found in terraform.tfvars" }
if (-not $ProjectName) { Write-Error "azuredevops_project_name not found in terraform.tfvars" }
if (-not $RepoName) { Write-Error "azuredevops_repository_name not found in terraform.tfvars" }

# Get PAT if not provided
if (-not $PAT) {
    Write-Host "`nAzure DevOps PAT required for API access." -ForegroundColor Yellow
    Write-Host "Create one at: https://dev.azure.com/$OrgName/_usersSettings/tokens" -ForegroundColor Yellow
    Write-Host "Required scopes: Code (Read & Write)" -ForegroundColor Yellow
    $secPAT = Read-Host "Enter PAT" -AsSecureString
    $PAT = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPAT)
    )
}

Write-Host "`nConfiguration:" -ForegroundColor Green
Write-Host "  Organization: $OrgName"
Write-Host "  Project: $ProjectName"
Write-Host "  Repository: $RepoName"

# Create auth header
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT"))
$headers = @{
    "Authorization" = "Basic $base64Auth"
    "Content-Type"  = "application/json"
}

$baseUrl = "https://dev.azure.com/$OrgName/$ProjectName/_apis"

# Function to make API calls
function Invoke-AzDoApi {
    param($Method, $Uri, $Body, [switch]$BodyIsArray)
    
    $params = @{
        Method = $Method
        Uri = $Uri
        Headers = $headers
    }
    if ($Body) {
        if ($BodyIsArray) {
            # Force array serialization - wrap in ArrayList and use explicit JSON
            $bodyArray = [System.Collections.ArrayList]@()
            [void]$bodyArray.Add($Body)
            $params.Body = "[$($Body | ConvertTo-Json -Depth 10 -Compress)]"
        } else {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
        }
    }
    
    try {
        Invoke-RestMethod @params
    }
    catch {
        Write-Host "API Error: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails.Message) {
            Write-Host $_.ErrorDetails.Message -ForegroundColor Red
        }
        throw
    }
}

# Get repository ID
Write-Host "`nGetting repository information..." -ForegroundColor Yellow
$repos = Invoke-AzDoApi -Method GET -Uri "$baseUrl/git/repositories?api-version=7.1"
$repo = $repos.value | Where-Object { $_.name -eq $RepoName }

if (-not $repo) {
    Write-Error "Repository '$RepoName' not found in project '$ProjectName'"
}

$repoId = $repo.id
Write-Host "Repository ID: $repoId" -ForegroundColor Green

# Define file contents
$readmeContent = @"
# Fabric Workspace Content Repository

This repository contains Microsoft Fabric workspace artifacts managed via Git integration and Azure DevOps pipelines.

## Architecture

This repository supports a **multi-workspace architecture** with three environments:

- **Dev Workspace** - Direct Git sync with dev branch (automatic synchronization)
- **Test Workspace** - Pipeline deployment from test branch (1 reviewer required)
- **Prod Workspace** - Pipeline deployment from main branch (2 reviewers required)

## Branches

- **main** - Production-ready content (deploys to prod workspace via pipeline)
- **test** - Testing/staging branch (deploys to test workspace via pipeline)
- **dev** - Development branch (syncs directly to dev workspace via Git integration)

## Directory Structure

``````
├── fabric-content/           # Fabric artifacts synced with workspace
│   ├── SampleModel.pbip     # Power BI Project files
│   └── ...
├── pipelines/                # Azure DevOps pipeline definitions
│   └── fabric-deploy.yaml   # Multi-workspace deployment pipeline
└── README.md
``````

## Deployment Workflows

### Dev Environment (Git Sync)
Push changes to the ``dev`` branch and they automatically sync to the dev workspace within minutes. No PR required.

``````bash
git checkout dev
git add fabric-content/
git commit -m "Update semantic model"
git push origin dev
# Content automatically syncs to dev workspace
``````

### Test Environment (Pipeline)
Create a PR to the ``test`` branch. After 1 reviewer approves, merge triggers the deployment pipeline.

``````bash
git checkout -b feature/new-report
# Make changes to fabric-content/
git add fabric-content/
git commit -m "Add new report"
git push origin feature/new-report
# Create PR to test branch in Azure DevOps
# After approval and merge, pipeline deploys to test workspace
``````

### Prod Environment (Pipeline)
Create a PR to the ``main`` branch. After 2 reviewers approve, merge triggers the deployment pipeline.

``````bash
# From test branch, create PR to main
# After 2 approvals and merge, pipeline deploys to prod workspace
``````

## Pipeline Details

The pipeline (``pipelines/fabric-deploy.yaml``) automatically:
- Detects target environment from branch name
- Loads the correct variable group (Fabric-Deployment-dev/test/prod)
- Authenticates using service principal
- Deploys all items from fabric-content/ directory
- Removes orphaned items from workspace

## Getting Started

1. Clone this repository
2. Create a feature branch from dev or test
3. Add your Fabric artifacts to fabric-content/
4. Commit and push changes
5. Follow the appropriate deployment workflow above
"@

$gitignoreContent = @"
# Terraform
*.tfstate
*.tfstate.*
.terraform/
*.tfvars
!*.tfvars.example

# IDE
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db

# Logs
*.log
"@

$fabricReadmeContent = @"
# Fabric Content

Place your Fabric workspace artifacts here. This directory syncs with your Fabric workspace via Git integration.
"@

$pipelineYamlContent = @'
# Microsoft Fabric Deployment Pipeline (Multi-Workspace)
# Deploys Fabric items (Semantic Models, Reports, Notebooks, etc.) using fabric_cicd library
# 
# Architecture:
# - Dev workspace: Direct Git sync (no pipeline deployment needed)
# - Test workspace: Deployed via pipeline on test branch
# - Prod workspace: Deployed via pipeline on main branch
#
# Triggers:
# - Dev branch: Changes to fabric-content/ (for pipeline testing only, actual deployment via Git sync)
# - Test branch: Changes to fabric-content/ (deploys to test workspace)
# - Main branch: Changes to fabric-content/ (deploys to prod workspace)
#
# Prerequisites:
# - Variable groups: Fabric-Deployment-dev, Fabric-Deployment-test, Fabric-Deployment-prod
# - Service principal with admin access to all workspaces
# - fabric_cicd library available on PyPI
# - Branch policies: test (1 reviewer), main (2 reviewers)

trigger:
  branches:
    include:
      - dev
      - test
      - main
  paths:
    include:
      - fabric-content/*

pr: none  # Don't run on PRs, only on merges

# Variable group is loaded dynamically based on branch name
variables:
- name: vmImage
  value: 'ubuntu-latest'
- name: pythonVersion 
  value: '3.11'

pool:
  vmImage: $(vmImage)

stages:
- stage: DetectEnvironment
  displayName: 'Detect Target Environment'
  jobs:
  - job: DetectEnv
    displayName: 'Map Branch to Environment'
    steps:
    - script: |
        BRANCH_NAME="$(Build.SourceBranchName)"
        echo "Source branch: $BRANCH_NAME"
        
        # Map branch name to environment
        if [ "$BRANCH_NAME" = "dev" ]; then
          DEPLOY_ENV="dev"
        elif [ "$BRANCH_NAME" = "test" ]; then
          DEPLOY_ENV="test"
        elif [ "$BRANCH_NAME" = "main" ]; then
          DEPLOY_ENV="prod"
        else
          echo "##vso[task.logissue type=error]Unknown branch: $BRANCH_NAME. Expected dev, test, or main."
          exit 1
        fi
        
        echo "Target environment: $DEPLOY_ENV"
        echo "##vso[task.setvariable variable=DEPLOY_ENV;isOutput=true]$DEPLOY_ENV"
      displayName: 'Detect Environment from Branch'
      name: DetectStep

- stage: DeployFabric
  displayName: 'Deploy to Fabric Workspace'
  dependsOn: DetectEnvironment
  variables:
    # Load all three variable groups - deployment script will use the correct one based on DEPLOY_ENV
    - name: DEPLOY_ENV
      value: $[ stageDependencies.DetectEnvironment.DetectEnv.outputs['DetectStep.DEPLOY_ENV'] ]
    - group: Fabric-Deployment-dev
    - group: Fabric-Deployment-test
    - group: Fabric-Deployment-prod
  jobs:
  - job: Deploy
    displayName: 'Deploy Fabric Items'
    
    steps:
    - checkout: self
      persistCredentials: true
      displayName: 'Checkout Repository'
    
    - task: UsePythonVersion@0
      displayName: 'Use Python $(pythonVersion)'
      inputs:
        versionSpec: '$(pythonVersion)'
        addToPath: true
    
    - script: |
        python -m pip install --upgrade pip
        pip install fabric-cicd azure-identity
      displayName: 'Install Dependencies'
    
    - script: |
        python - << 'EOF'
        """
        Microsoft Fabric Deployment using fabric_cicd library
        
        Deploys Fabric items (Semantic Models, Reports, Notebooks, etc.) 
        from the repository to a Fabric workspace.
        """
        import sys
        import os
        from pathlib import Path

        from azure.identity import ClientSecretCredential
        from fabric_cicd import FabricWorkspace, publish_all_items, unpublish_all_orphan_items, change_log_level


        def main():
            """Main deployment function."""
            
            # Force unbuffered output for real-time logging in pipelines
            sys.stdout.reconfigure(line_buffering=True, write_through=True)
            sys.stderr.reconfigure(line_buffering=True, write_through=True)
            
            # Enable debugging if SYSTEM_DEBUG is set in Azure DevOps pipeline
            if os.getenv("SYSTEM_DEBUG", "false").lower() == "true":
                change_log_level("DEBUG")
                print("[DEBUG] Debug logging enabled")
            
            print("=" * 70)
            print("Microsoft Fabric Deployment using fabric_cicd")
            print("=" * 70)
            
            # Get environment from DEPLOY_ENV variable 
            environment = os.getenv("DEPLOY_ENV", "test")
            env_upper = environment.upper()
            
            print(f"Target Environment: {environment} (loading {env_upper} variables)")
            
            # Get environment-specific variables
            # Variable names are suffixed with environment (e.g., FABRIC_WORKSPACE_ID_TEST)
            # This prevents conflicts when multiple variable groups are loaded
            workspace_id = os.getenv(f"FABRIC_WORKSPACE_ID_{env_upper}")
            client_id = os.getenv(f"SERVICE_PRINCIPAL_ID_{env_upper}")
            client_secret = os.getenv(f"SERVICE_PRINCIPAL_SECRET_{env_upper}")
            tenant_id = os.getenv(f"AZURE_TENANT_ID_{env_upper}")
            
            # Validate required variables
            missing = []
            if not workspace_id: missing.append(f"FABRIC_WORKSPACE_ID_{env_upper}")
            if not client_id: missing.append(f"SERVICE_PRINCIPAL_ID_{env_upper}")
            if not client_secret: missing.append(f"SERVICE_PRINCIPAL_SECRET_{env_upper}")
            if not tenant_id: missing.append(f"AZURE_TENANT_ID_{env_upper}")
            
            if missing:
                print(f"[ERROR] Missing required environment variables: {', '.join(missing)}")
                return 1
            
            print(f"Environment: {environment}")
            print(f"Workspace ID: {workspace_id}")
            print(f"Tenant ID: {tenant_id}")
            print(f"Client ID: {client_id}")
            print("=" * 70)
            
            # Set repository directory (fabric-content folder)
            # In Azure DevOps, we're at the repository root
            repository_directory = str(Path.cwd() / "fabric-content")
            
            if not Path(repository_directory).exists():
                print(f"[ERROR] Repository directory not found: {repository_directory}")
                return 1
            
            print(f"Repository directory: {repository_directory}")
            
            # Define item types to deploy
            # Adjust based on what you have in your fabric-content folder
            item_type_in_scope = [
                "SemanticModel",
                "Report", 
                "Notebook",
                "DataPipeline",
                "Environment",
                "Lakehouse",
                "Warehouse"
            ]
            
            print(f"Item types in scope: {', '.join(item_type_in_scope)}")
            print()
            
            try:
                # Authenticate using service principal
                print("[AUTH] Authenticating with service principal...")
                token_credential = ClientSecretCredential(
                    client_id=client_id,
                    client_secret=client_secret,
                    tenant_id=tenant_id
                )
                print("[OK] Authentication credential created")
                
                # Initialize Fabric workspace
                print(f"\n[INIT] Initializing Fabric workspace connection...")
                target_workspace = FabricWorkspace(
                    workspace_id=workspace_id,
                    environment=environment,
                    repository_directory=repository_directory,
                    item_type_in_scope=item_type_in_scope,
                    token_credential=token_credential,
                )
                print("[OK] Workspace connection established")
                
                # Publish all items from repository
                print(f"\n[DEPLOY] Publishing items from repository...")
                publish_all_items(target_workspace)
                print("[OK] Items published successfully")
                
                # Unpublish orphan items (items in workspace but not in repository)
                print(f"\n[CLEANUP] Unpublishing orphan items...")
                unpublish_all_orphan_items(target_workspace)
                print("[OK] Orphan items removed")
                
                print("\n" + "=" * 70)
                print("[SUCCESS] Fabric workspace deployment completed!")
                print("=" * 70)
                return 0
                
            except Exception as e:
                print(f"\n[ERROR] Deployment failed: {e}")
                import traceback
                traceback.print_exc()
                return 1


        if __name__ == "__main__":
            sys.exit(main())
        EOF
      displayName: 'Deploy to Fabric Workspace'
      env:
        # Environment indicator - determines which variables to use
        DEPLOY_ENV: $(DEPLOY_ENV)
        # Dev environment variables
        FABRIC_WORKSPACE_ID_DEV: $(FABRIC_WORKSPACE_ID_DEV)
        SERVICE_PRINCIPAL_ID_DEV: $(SERVICE_PRINCIPAL_ID_DEV)
        SERVICE_PRINCIPAL_SECRET_DEV: $(SERVICE_PRINCIPAL_SECRET_DEV)
        AZURE_TENANT_ID_DEV: $(AZURE_TENANT_ID_DEV)
        # Test environment variables
        FABRIC_WORKSPACE_ID_TEST: $(FABRIC_WORKSPACE_ID_TEST)
        SERVICE_PRINCIPAL_ID_TEST: $(SERVICE_PRINCIPAL_ID_TEST)
        SERVICE_PRINCIPAL_SECRET_TEST: $(SERVICE_PRINCIPAL_SECRET_TEST)
        AZURE_TENANT_ID_TEST: $(AZURE_TENANT_ID_TEST)
        # Prod environment variables
        FABRIC_WORKSPACE_ID_PROD: $(FABRIC_WORKSPACE_ID_PROD)
        SERVICE_PRINCIPAL_ID_PROD: $(SERVICE_PRINCIPAL_ID_PROD)
        SERVICE_PRINCIPAL_SECRET_PROD: $(SERVICE_PRINCIPAL_SECRET_PROD)
        AZURE_TENANT_ID_PROD: $(AZURE_TENANT_ID_PROD)
        # Debug flag
        SYSTEM_DEBUG: $(System.Debug)
'@

# Function to create a push with multiple changes
function New-Push {
    param(
        [string]$BranchName,
        [string]$OldObjectId,
        [array]$Changes,
        [string]$Comment
    )
    
    $refUpdates = @(
        @{
            name = "refs/heads/$BranchName"
            oldObjectId = $OldObjectId
        }
    )
    
    $commits = @(
        @{
            comment = $Comment
            changes = $Changes
        }
    )
    
    $push = @{
        refUpdates = $refUpdates
        commits = $commits
    }
    
    Invoke-AzDoApi -Method POST -Uri "$baseUrl/git/repositories/$repoId/pushes?api-version=7.1" -Body $push
}

# Check if repo already has commits
Write-Host "`nChecking repository state..." -ForegroundColor Yellow
$mainCommitId = $null
$needsInitialCommit = $true
$devRef = $null
$testRef = $null
$masterRef = $null

try {
    $refs = Invoke-AzDoApi -Method GET -Uri "$baseUrl/git/repositories/$repoId/refs?api-version=7.1"
    $mainRef = $refs.value | Where-Object { $_.name -eq "refs/heads/main" }
    $masterRef = $refs.value | Where-Object { $_.name -eq "refs/heads/master" }
    $devRef = $refs.value | Where-Object { $_.name -eq "refs/heads/dev" }
    $testRef = $refs.value | Where-Object { $_.name -eq "refs/heads/test" }
    
    if ($mainRef) {
        Write-Host "Main branch exists with commit: $($mainRef.objectId)" -ForegroundColor Cyan
        $mainCommitId = $mainRef.objectId
        $needsInitialCommit = $false
    } elseif ($masterRef) {
        # Use master's commit to create main
        Write-Host "Master branch exists, will use its commit for main branch" -ForegroundColor Yellow
        $mainCommitId = $masterRef.objectId
    }
}
catch {
    # Empty repo - refs endpoint may fail
    Write-Host "Repository appears to be empty. Proceeding with initialization..." -ForegroundColor Green
}

# For empty repo, use all zeros as oldObjectId
$emptyObjectId = "0000000000000000000000000000000000000000"

# Create main branch if needed
if ($needsInitialCommit) {
    if ($masterRef -and $mainCommitId) {
        # Create main branch from master's commit
        Write-Host "`nCreating main branch from master..." -ForegroundColor Yellow
        $mainRefUpdate = @{
            name = "refs/heads/main"
            oldObjectId = $emptyObjectId
            newObjectId = $mainCommitId
        }
        Invoke-AzDoApi -Method POST -Uri "$baseUrl/git/repositories/$repoId/refs?api-version=7.1" -Body $mainRefUpdate -BodyIsArray
        Write-Host "Main branch created from master with commit: $mainCommitId" -ForegroundColor Green
    } else {
        # Create initial commit on main branch
        Write-Host "`nCreating initial commit on main branch..." -ForegroundColor Yellow

        $initialChanges = @(
            @{
                changeType = "add"
                item = @{ path = "/README.md" }
                newContent = @{
                    content = $readmeContent
                    contentType = "rawtext"
                }
            },
            @{
                changeType = "add"
                item = @{ path = "/.gitignore" }
                newContent = @{
                    content = $gitignoreContent
                    contentType = "rawtext"
                }
            },
            @{
                changeType = "add"
                item = @{ path = "/fabric-content/README.md" }
                newContent = @{
                    content = $fabricReadmeContent
                    contentType = "rawtext"
                }
            },
            @{
                changeType = "add"
                item = @{ path = "/pipelines/fabric-deploy.yaml" }
                newContent = @{
                    content = $pipelineYamlContent
                    contentType = "rawtext"
                }
            }
        )

        $mainPush = New-Push -BranchName "main" -OldObjectId $emptyObjectId -Changes $initialChanges -Comment "Initial commit: Repository structure and configuration"
        $mainCommitId = $mainPush.commits[0].commitId
        Write-Host "Main branch created with commit: $mainCommitId" -ForegroundColor Green
    }
} else {
    Write-Host "`nMain branch already exists, skipping initial commit." -ForegroundColor Cyan
    
    # Collect any missing files to add in a single push
    $missingFiles = @()
    
    # Check for fabric-content folder on main
    Write-Host "Checking for fabric-content folder on main branch..." -ForegroundColor Yellow
    try {
        $items = Invoke-AzDoApi -Method GET -Uri "$baseUrl/git/repositories/$repoId/items?scopePath=/fabric-content&versionDescriptor.version=main&versionDescriptor.versionType=branch&api-version=7.1"
        Write-Host "  fabric-content folder exists on main branch" -ForegroundColor Cyan
    }
    catch {
        Write-Host "  fabric-content folder missing on main branch" -ForegroundColor Yellow
        $missingFiles += @{
            changeType = "add"
            item = @{ path = "/fabric-content/README.md" }
            newContent = @{
                content = $fabricReadmeContent
                contentType = "rawtext"
            }
        }
    }
    
    # Check for pipeline YAML on main - always update to ensure latest version
    Write-Host "Checking for pipeline YAML on main branch..." -ForegroundColor Yellow
    try {
        $items = Invoke-AzDoApi -Method GET -Uri "$baseUrl/git/repositories/$repoId/items?scopePath=/pipelines/fabric-deploy.yaml&versionDescriptor.version=main&versionDescriptor.versionType=branch&api-version=7.1"
        Write-Host "  pipeline YAML exists, updating to latest version" -ForegroundColor Yellow
        $missingFiles += @{
            changeType = "edit"
            item = @{ path = "/pipelines/fabric-deploy.yaml" }
            newContent = @{
                content = $pipelineYamlContent
                contentType = "rawtext"
            }
        }
    }
    catch {
        Write-Host "  pipeline YAML missing on main branch" -ForegroundColor Yellow
        $missingFiles += @{
            changeType = "add"
            item = @{ path = "/pipelines/fabric-deploy.yaml" }
            newContent = @{
                content = $pipelineYamlContent
                contentType = "rawtext"
            }
        }
    }
    
    # Add or update files if any
    if ($missingFiles.Count -gt 0) {
        Write-Host "Updating $($missingFiles.Count) file(s) on main branch..." -ForegroundColor Yellow
        $mainPush = New-Push -BranchName "main" -OldObjectId $mainCommitId -Changes $missingFiles -Comment "Update repository files (fabric-content and/or pipeline)"
        $mainCommitId = $mainPush.commits[0].commitId
        Write-Host "  Files updated on main branch" -ForegroundColor Green
    }
}

# Function to ensure fabric-content folder exists on a branch
function Ensure-FabricContentFolder {
    param(
        [string]$BranchName,
        [string]$CommitId
    )
    
    # Check if fabric-content folder exists
    try {
        $items = Invoke-AzDoApi -Method GET -Uri "$baseUrl/git/repositories/$repoId/items?scopePath=/fabric-content&versionDescriptor.version=$BranchName&versionDescriptor.versionType=branch&api-version=7.1"
        Write-Host "  fabric-content folder exists on $BranchName branch" -ForegroundColor Cyan
        return $false  # No changes needed
    }
    catch {
        # Folder doesn't exist, need to create it
        Write-Host "  fabric-content folder missing on $BranchName branch, adding..." -ForegroundColor Yellow
        return $true  # Changes needed
    }
}

# Create dev branch from main (if it doesn't exist)
if (-not $devRef) {
    Write-Host "`nCreating dev branch..." -ForegroundColor Yellow

    $devRefUpdate = @{
        name = "refs/heads/dev"
        oldObjectId = $emptyObjectId
        newObjectId = $mainCommitId
    }

    $devResult = Invoke-AzDoApi -Method POST -Uri "$baseUrl/git/repositories/$repoId/refs?api-version=7.1" -Body $devRefUpdate -BodyIsArray
    Write-Host "Dev branch created" -ForegroundColor Green
    $devRef = @{ objectId = $mainCommitId }
} else {
    Write-Host "`nDev branch already exists" -ForegroundColor Cyan
    
    # Collect any missing files to add in a single push
    $missingFilesDev = @()
    
    # Check for fabric-content folder on dev
    $needsFabricContent = Ensure-FabricContentFolder -BranchName "dev" -CommitId $devRef.objectId
    if ($needsFabricContent) {
        $missingFilesDev += @{
            changeType = "add"
            item = @{ path = "/fabric-content/README.md" }
            newContent = @{
                content = $fabricReadmeContent
                contentType = "rawtext"
            }
        }
    }
    
    # Check for pipeline YAML on dev - always update to ensure latest version
    Write-Host "Checking for pipeline YAML on dev branch..." -ForegroundColor Yellow
    try {
        $items = Invoke-AzDoApi -Method GET -Uri "$baseUrl/git/repositories/$repoId/items?scopePath=/pipelines/fabric-deploy.yaml&versionDescriptor.version=dev&versionDescriptor.versionType=branch&api-version=7.1"
        Write-Host "  pipeline YAML exists, updating to latest version" -ForegroundColor Yellow
        $missingFilesDev += @{
            changeType = "edit"
            item = @{ path = "/pipelines/fabric-deploy.yaml" }
            newContent = @{
                content = $pipelineYamlContent
                contentType = "rawtext"
            }
        }
    }
    catch {
        Write-Host "  pipeline YAML missing on dev branch, adding..." -ForegroundColor Yellow
        $missingFilesDev += @{
            changeType = "add"
            item = @{ path = "/pipelines/fabric-deploy.yaml" }
            newContent = @{
                content = $pipelineYamlContent
                contentType = "rawtext"
            }
        }
    }
    
    # Add or update files if any
    if ($missingFilesDev.Count -gt 0) {
        Write-Host "Updating $($missingFilesDev.Count) file(s) on dev branch..." -ForegroundColor Yellow
        $devPush = New-Push -BranchName "dev" -OldObjectId $devRef.objectId -Changes $missingFilesDev -Comment "Update repository files (fabric-content and/or pipeline)"
        Write-Host "  Files updated on dev branch" -ForegroundColor Green
        $devRef.objectId = $devPush.commits[0].commitId
    }
}

# Create test branch from main (if it doesn't exist)
if (-not $testRef) {
    Write-Host "`nCreating test branch..." -ForegroundColor Yellow

    $testRefUpdate = @{
        name = "refs/heads/test"
        oldObjectId = $emptyObjectId
        newObjectId = $mainCommitId
    }

    $testResult = Invoke-AzDoApi -Method POST -Uri "$baseUrl/git/repositories/$repoId/refs?api-version=7.1" -Body $testRefUpdate -BodyIsArray
    Write-Host "Test branch created" -ForegroundColor Green
    $testRef = @{ objectId = $mainCommitId }
} else {
    Write-Host "`nTest branch already exists" -ForegroundColor Cyan
    
    # Collect any missing files to add in a single push
    $missingFilesTest = @()
    
    # Check for fabric-content folder on test
    $needsFabricContent = Ensure-FabricContentFolder -BranchName "test" -CommitId $testRef.objectId
    if ($needsFabricContent) {
        $missingFilesTest += @{
            changeType = "add"
            item = @{ path = "/fabric-content/README.md" }
            newContent = @{
                content = $fabricReadmeContent
                contentType = "rawtext"
            }
        }
    }
    
    # Check for pipeline YAML on test - always update to ensure latest version
    Write-Host "Checking for pipeline YAML on test branch..." -ForegroundColor Yellow
    try {
        $items = Invoke-AzDoApi -Method GET -Uri "$baseUrl/git/repositories/$repoId/items?scopePath=/pipelines/fabric-deploy.yaml&versionDescriptor.version=test&versionDescriptor.versionType=branch&api-version=7.1"
        Write-Host "  pipeline YAML exists, updating to latest version" -ForegroundColor Yellow
        $missingFilesTest += @{
            changeType = "edit"
            item = @{ path = "/pipelines/fabric-deploy.yaml" }
            newContent = @{
                content = $pipelineYamlContent
                contentType = "rawtext"
            }
        }
    }
    catch {
        Write-Host "  pipeline YAML missing on test branch, adding..." -ForegroundColor Yellow
        $missingFilesTest += @{
            changeType = "add"
            item = @{ path = "/pipelines/fabric-deploy.yaml" }
            newContent = @{
                content = $pipelineYamlContent
                contentType = "rawtext"
            }
        }
    }
    
    # Add or update files if any
    if ($missingFilesTest.Count -gt 0) {
        Write-Host "Updating $($missingFilesTest.Count) file(s) on test branch..." -ForegroundColor Yellow
        $testPush = New-Push -BranchName "test" -OldObjectId $testRef.objectId -Changes $missingFilesTest -Comment "Update repository files (fabric-content and/or pipeline)"
        Write-Host "  Files updated on test branch" -ForegroundColor Green
        $testRef.objectId = $testPush.commits[0].commitId
    }
}

# Set main as the default branch
Write-Host "`nSetting main as default branch..." -ForegroundColor Yellow
$updateRepo = @{
    defaultBranch = "refs/heads/main"
}
$updateResult = Invoke-AzDoApi -Method PATCH -Uri "$baseUrl/git/repositories/$repoId`?api-version=7.1" -Body $updateRepo
Write-Host "Default branch set to main" -ForegroundColor Green

# Delete master branch if it exists (now that main is default)
if ($masterRef) {
    Write-Host "`nDeleting master branch..." -ForegroundColor Yellow
    $deleteMaster = @{
        name = "refs/heads/master"
        oldObjectId = $masterRef.objectId
        newObjectId = "0000000000000000000000000000000000000000"
    }
    Invoke-AzDoApi -Method POST -Uri "$baseUrl/git/repositories/$repoId/refs?api-version=7.1" -Body $deleteMaster -BodyIsArray
    Write-Host "Master branch deleted" -ForegroundColor Green
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Repository initialized successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "`nBranches created:"
Write-Host "  - main (default) - deploys to prod workspace via pipeline" -ForegroundColor Cyan
Write-Host "  - test - deploys to test workspace via pipeline" -ForegroundColor Cyan
Write-Host "  - dev - syncs directly to dev workspace (Git integration)" -ForegroundColor Cyan
Write-Host "`nFiles created:"
Write-Host "  - README.md (repository documentation)" -ForegroundColor Gray
Write-Host "  - .gitignore (ignore Terraform state and secrets)" -ForegroundColor Gray
Write-Host "  - fabric-content/ (folder for Fabric artifacts)" -ForegroundColor Gray
Write-Host "  - pipelines/fabric-deploy.yaml (multi-workspace deployment pipeline)" -ForegroundColor Gray
Write-Host "`nRepository URL:" -ForegroundColor Yellow
Write-Host "  https://dev.azure.com/$OrgName/$([uri]::EscapeDataString($ProjectName))/_git/$RepoName"
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "  1. Update terraform.tfvars: enable_dev_git_integration = true"
Write-Host "  2. Run: terraform apply"
Write-Host "  3. Add your Fabric content to the fabric-content/ folder"
Write-Host "  4. Push to dev branch for automatic sync, or PR to test/main for pipeline deployment"
Write-Host ""
