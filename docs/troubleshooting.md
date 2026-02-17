# Troubleshooting Guide for Microsoft Fabric Terraform

This guide helps you resolve common issues when deploying and managing Microsoft Fabric workspaces with Terraform.

## 🔧 Quick Diagnostics

First, run the built-in diagnostic tools:

```powershell
# Check prerequisites and configuration
.\scripts\validate-setup.ps1 -Detailed

# Test Azure authentication
az account show
az account list-locations --query "[?displayName=='East US 2']"

# Validate Terraform configuration
terraform validate
terraform plan
```

## 🏗️ Terraform Issues

### Issue: Terraform Version Compatibility

**Error Messages:**
```
Error: Unsupported Terraform Core version
Error: Required version constraint not satisfied
```

**Solutions:**
```powershell
# Check current version
terraform version

# Update Terraform (Windows)
winget upgrade Hashicorp.Terraform

# Verify version >= 1.8.0
terraform version | Select-String "v(\d+\.\d+)"
```

### Issue: Provider Authentication Failure

**Error Messages:**
```
Error: building Azure Client: obtain subscription() from Azure CLI
Error: Error building ARM Config: obtain subscription from Azure CLI
```

**Solutions:**
```powershell
# Re-authenticate to Azure
az logout
az login --tenant <your-tenant-id>

# Set correct subscription
az account set --subscription <your-subscription-id>

# Verify authentication
az account show --query "{name:name, id:id, tenantId:tenantId}"

# For service principal OIDC
$env:ARM_USE_OIDC = "true"
$env:ARM_TENANT_ID = "<tenant-id>"
$env:ARM_CLIENT_ID = "<client-id>"
```

### Issue: Backend State Configuration

**Error Messages:**
```
Error: Failed to get existing workspaces: storage account not found
Error: Error building ARM Config for backend
```

**Solutions:**
```powershell
# Verify backend configuration
Get-Content backend.hcl

# Check storage account exists
az storage account show --name <storage-account-name> --resource-group <resource-group>

# Recreate storage if needed
$storageAccount = "tfstate$(Get-Random -Minimum 100000 -Maximum 999999)"
az storage account create --resource-group rg-terraform-state --name $storageAccount --sku Standard_LRS

# Re-initialize Terraform
Remove-Item .terraform -Recurse -Force -ErrorAction SilentlyContinue
terraform init -backend-config=backend.hcl
```

## 🚀 Microsoft Fabric Issues

### Issue: Fabric Capacity Not Found

**Error Messages:**
```
Error: Cannot find capacity with ID
Error: Capacity not accessible or does not exist
```

**Solutions:**
```powershell
# Verify capacity exists and get details
az rest --method GET --uri "https://api.fabric.microsoft.com/v1/capacities" --resource "https://api.fabric.microsoft.com/"

# Check capacity from Azure Portal
Start-Process "https://portal.azure.com/#browse/Microsoft.Fabric%2Fcapacities"

# Verify capacity ID format (should be uppercase GUID)
$capacityId = "12345678-1234-1234-1234-123456789ABC"
if ($capacityId -match "^[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}$") {
    Write-Host "✅ Valid format"
} else {
    Write-Host "❌ Invalid format - must be uppercase GUID"
}
```

**Common Capacity Issues:**
- **Trial Capacity**: Not supported by Terraform provider
- **Paused Capacity**: Must be active/running
- **Wrong Region**: Capacity and resources should be in same region
- **Insufficient Permissions**: Need capacity admin rights

### Issue: Fabric Workspace Creation Fails

**Error Messages:**
```
Error: Cannot create workspace in capacity
Error: Workspace name already exists
Error: Insufficient permissions to create workspace
```

**Solutions:**
```powershell
# Check workspace name uniqueness
$workspaceName = "Your Workspace Name"
# Workspace names must be unique within the tenant
# This configuration creates 3 workspaces: dev, test, and prod

# Verify capacity has available slots
# Each capacity SKU has limits on workspace count
# See "Workspace Count Limit Exceeded" section below

# Check user permissions
# User must have workspace creation rights in the capacity

# Try different workspace name prefix
# Update terraform.tfvars with unique workspace_name_prefix
```

### Issue: Git Integration Fails

**Error Messages:**
```
Error: Cannot configure Git integration
Error: Repository not accessible
```

**Solutions:**
```powershell
# IMPORTANT: Only the DEV workspace has Git integration enabled
# Test and prod workspaces use pipeline deployment instead
# See "Git Integration Only Works in Dev Workspace" section below

# Verify Azure DevOps repository exists
az repos show --repository <repo-name> --organization <org-name> --project <project-name>

# Check repository permissions
# Service principal needs read/write access to repository

# Verify branch exists (dev branch required for dev workspace)
git ls-remote --heads https://dev.azure.com/<org>/<project>/_git/<repo>

# Manual Git setup in Fabric workspace
# Navigate to workspace settings and configure Git manually if needed
```

## 🔄 Azure DevOps Issues

### Issue: Azure DevOps Authentication

**Error Messages:**
```
Error: HTTP 401 Unauthorized when accessing Azure DevOps
Error: Personal access token has expired
```

**Solutions:**
```powershell
# For service connection errors - verify OIDC setup
az ad app show --id <client-id> --query "signInAudience,keyCredentials,federatedIdentityCredentials"

# Check service connection in Azure DevOps
Start-Process "https://dev.azure.com/<org>/<project>/_settings/adminservices"

# Verify organization permissions
# User needs Project Collection Administrator rights

# Recreate service connection if needed
# Delete and recreate via Terraform or portal
```

### Issue: Pipeline Creation/Execution Fails

**Error Messages:**
```
Error: Pipeline YAML not found
Error: Agent pool not found
Error: Service connection not authorized
```

**Solutions:**
```powershell
# Verify pipeline YAML exists in repository
Test-Path "pipelines/fabric-deploy.yaml"

# Check agent pool availability
# Default: 'ubuntu-latest' (Microsoft-hosted agents)

# Authorize service connection for pipeline
# Go to Azure DevOps > Project Settings > Service Connections
# Select connection and authorize for all pipelines

# Validate pipeline YAML
az pipelines create --name "test-pipeline" --yaml-path "pipelines/fabric-deploy.yaml" --repository-type tfsgit
```

### Issue: Variable Group Access

**Error Messages:**
```
Error: Variable group not found
Error: Access denied to variable group
```

**Solutions:**
```powershell
# Check if all three variable groups exist (one per environment)
az pipelines variable-group list --organization <org> --project <project> --query "[?contains(name, 'Fabric-Deployment')]"

# Should return: Fabric-Deployment-dev, Fabric-Deployment-test, Fabric-Deployment-prod
# If missing, see "Variable Group Not Found" section below

# Grant pipeline access to variable groups
# In Azure DevOps: Library > Variable Groups > Security

# Verify variable values are set for each group
az pipelines variable-group variable list --group-id <group-id> --organization <org> --project <project>
```

### Issue: Branch Policy Blocks Repository Initialization

**Error Messages:**
```
API Error: Response status code does not indicate success: 403 (Forbidden)
TF402455: Pushes to this branch are not permitted; you must use a pull request to update this branch
GitRefUpdateRejectedByPolicyException
```

**Cause:**
The `init-repo-remote.ps1` script tries to push directly to main/test branches, but branch policies are already created requiring PRs.

**Solution:**
This is why we use two-phase deployment:

```powershell
# Phase 1: Deploy WITHOUT branch policies (enable_dev_git_integration = false)
# Edit terraform.tfvars
enable_dev_git_integration = false

terraform apply

# Initialize the repository (this script needs direct push access)
$env:AZURE_DEVOPS_PAT = "your-pat"
.\scripts\init-repo-remote.ps1

# Phase 2: Enable Git integration AND branch policies (enable_dev_git_integration = true)
# Edit terraform.tfvars
enable_dev_git_integration = true

terraform apply
```

**If You Already Applied with Branch Policies:**
```powershell
# Option 1: Temporarily disable policies in Azure DevOps portal
# Go to: Repos > Branches > [branch] > Branch Policies > Disable all
# Run: .\scripts\init-repo-remote.ps1
# Then: terraform apply (to re-enable policies)

# Option 2: Delete and recreate (if no important data)
terraform destroy -target=azuredevops_branch_policy_min_reviewers.test_branch_policy
terraform destroy -target=azuredevops_branch_policy_min_reviewers.main_branch_policy
terraform destroy -target=azuredevops_branch_policy_build_validation.test_branch_build_policy
terraform destroy -target=azuredevops_branch_policy_build_validation.main_branch_build_policy

# Run init script
.\scripts\init-repo-remote.ps1

# Recreate policies
terraform apply
```

## 🔐 Authentication & Permissions Issues

### Issue: OIDC Authentication Fails

**Error Messages:**
```
Error: AADSTS70021: No matching federated identity record found
Error: The requested identity token is invalid
```

**Solutions:**
```powershell
# Verify federated identity credential configuration
az rest --method GET --uri "https://graph.microsoft.com/beta/applications/<object-id>/federatedIdentityCredentials"

# Check issuer and subject match exactly
# For Azure DevOps: https://vstoken.dev.azure.com/<org>
# Subject: sc://<org>/<project>/<service-connection-name>

# Recreate federated credential
$body = @{
    name = "AzureDevOps-OIDC"
    issuer = "https://vstoken.dev.azure.com/<org>"
    subject = "sc://<org>/<project>/<service-connection>"
    audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json

az rest --method POST --uri "https://graph.microsoft.com/beta/applications/<object-id>/federatedIdentityCredentials" --body $body
```

### Issue: Insufficient Azure Permissions

**Error Messages:**
```
Error: The client does not have authorization to perform action
Error: Forbidden - insufficient privileges
```

**Solutions:**
```powershell
# Check current role assignments
az role assignment list --assignee <user-or-sp-id> --include-inherited

# Assign required roles
az role assignment create --assignee <principal-id> --role "Contributor" --scope "/subscriptions/<sub-id>"
az role assignment create --assignee <principal-id> --role "User Access Administrator" --scope "/subscriptions/<sub-id>"

# For Key Vault access
az role assignment create --assignee <principal-id> --role "Key Vault Administrator" --scope "/subscriptions/<sub-id>"

# Wait for role propagation (up to 5 minutes)
Start-Sleep 300
```

## 🌐 Network and Connectivity Issues

### Issue: Firewall/Network Restrictions

**Error Messages:**
```
Error: Failed to connect to azure.microsoft.com
Error: Connection timeout
```

**Solutions:**
```powershell
# Test connectivity to required endpoints
Test-NetConnection -ComputerName "management.azure.com" -Port 443
Test-NetConnection -ComputerName "login.microsoftonline.com" -Port 443
Test-NetConnection -ComputerName "api.fabric.microsoft.com" -Port 443

# Configure corporate firewall/proxy if needed
# Whitelist required Azure endpoints
# Configure proxy settings for tools
```

### Issue: Private Endpoints/VNet Restrictions

**Error Messages:**
```
Error: Storage account not accessible
Error: Key Vault access denied from current location
```

**Solutions:**
```powershell
# Check if resources have private endpoints
az storage account show --name <storage-account> --query "networkRuleSet"
az keyvault show --name <keyvault-name> --query "networkAcls"

# Temporarily allow public access for deployment
az storage account update --name <storage-account> --resource-group <rg> --default-action Allow
az keyvault update --name <keyvault-name> --resource-group <rg> --default-action Allow

# Or deploy from within VNet/approved location
```

## 🏢 Multi-Workspace Issues

### Issue: Git Integration Only Works in Dev Workspace

**Problem:**
Users attempt to configure Git sync on test or prod workspaces in the Fabric portal but find it's not available or doesn't match the repository configuration.

**Explanation:**
By design, only the **dev workspace** has Git integration enabled. This follows the deployment pattern where:
- **Dev workspace**: Direct Git sync for development work
- **Test workspace**: Receives deployments via pipeline from test branch
- **Prod workspace**: Receives deployments via pipeline from main branch

**Solution:**
```powershell
# Verify only dev workspace has Git integration
terraform state show 'fabric_workspace.main["dev"]' | Select-String "git_integration"

# To change Git configuration
# 1. Update terraform.tfvars to modify dev workspace Git settings only
# 2. Test/prod workspaces use deployment pipelines instead

# View workspace configurations
Get-Content fabric-workspace.tf | Select-String -Context 2,2 "enable_git_integration"
```

**Key Points:**
- Test/prod workspaces intentionally don't have Git sync
- Use pipelines to deploy to test/prod environments
- Only dev workspace syncs directly with repository dev branch

### Issue: Workspace Count Limit Exceeded

**Error Messages:**
```
Error: Cannot create workspace in capacity
Error: Capacity workspace limit reached
Error: Maximum number of workspaces exceeded for this SKU
```

**Problem:**
The Fabric capacity SKU doesn't support creating 3 workspaces (dev, test, prod).

**Capacity Limits by SKU:**
- **F2**: Maximum 1 workspace
- **F4**: Maximum 2 workspaces  
- **F8**: Maximum 3+ workspaces
- **F16+**: Maximum 10+ workspaces

**Solutions:**
```powershell
# Check current capacity SKU
az rest --method GET --uri "https://api.fabric.microsoft.com/v1/capacities/<capacity-id>" --resource "https://api.fabric.microsoft.com/" --query "sku"

# Option 1: Upgrade capacity SKU (recommended)
# Upgrade to F8 or higher in Azure Portal
Start-Process "https://portal.azure.com/#browse/Microsoft.Fabric%2Fcapacities"

# Option 2: Reduce workspace count
# Edit fabric-workspace.tf to only create dev and test workspaces
# Remove prod from the for_each environments

# Example: Create only dev and test
# In fabric-workspace.tf, change:
# for_each = var.environments
# To:
# for_each = { for k, v in var.environments : k => v if k != "prod" }
```

**Prevention:**
- Verify capacity SKU supports required workspace count before deployment
- Use F8 or higher capacity for full dev/test/prod setup

### Issue: Wrong Workspace Deployed To

**Error Messages:**
```
Error: Workspace ID mismatch
Warning: Deploying to unexpected workspace
```

**Problem:**
The deployment pipeline deploys content to the wrong environment/workspace (e.g., test content goes to prod).

**Root Cause:**
Branch name doesn't match the expected pattern, causing incorrect variable group selection:
- Branch `dev` → Fabric-Deployment-dev → dev workspace
- Branch `test` → Fabric-Deployment-test → test workspace  
- Branch `main` → Fabric-Deployment-prod → prod workspace

**Solutions:**
```powershell
# Verify current branch
git branch --show-current

# Check pipeline variable group mapping
# In pipelines/fabric-deploy.yaml, verify:
Get-Content pipelines/fabric-deploy.yaml | Select-String "Fabric-Deployment"

# Ensure branch names match exactly
git branch -a

# Create missing branches if needed
git checkout -b test
git push origin test
git checkout -b main  
git push origin main

# Verify variable groups contain correct workspace IDs
az pipelines variable-group list --organization <org> --project <project> | ConvertFrom-Json | Where-Object { $_.name -like "Fabric-Deployment-*" } | ForEach-Object {
    Write-Host "\n$($_.name):"
    $_.variables.PSObject.Properties | ForEach-Object { Write-Host "  $($_.Name) = $($_.Value.value)" }
}
```

**Prevention:**
- Always merge to correct branch: dev → test → main
- Verify branch name before triggering pipeline
- Review pipeline logs to confirm workspace target

### Issue: Variable Group Not Found

**Error Messages:**
```
Error: Could not find variable group 'Fabric-Deployment-dev'
Error: Could not find variable group 'Fabric-Deployment-test'
Error: Could not find variable group 'Fabric-Deployment-prod'
```

**Problem:**
Pipeline cannot find the required variable group for the environment.

**Root Causes:**
1. Variable groups not created during Terraform apply
2. Incorrect naming (missing hyphen, wrong case)
3. Variable groups exist but pipeline lacks permissions

### Issue: Missing Environment-Specific Variables

**Error Messages:**
```
Error: Invalid tenant ID provided
Error: Missing required environment variables: FABRIC_WORKSPACE_ID_TEST
Error: workspace_id parameter is required
```

**Problem:**
Pipeline can't find environment-specific variables like `FABRIC_WORKSPACE_ID_TEST`, `SERVICE_PRINCIPAL_ID_PROD`, etc.

**Root Causes:**
1. Variable groups still use old naming convention (without environment suffix)
2. Terraform changes not applied after variable naming update
3. Pipeline YAML not updated to use new variable names

**Solutions:**
```powershell
# 1. Apply Terraform changes to update variable groups with new names
terraform apply

# 2. Run init script to update pipeline YAML on all branches
$env:AZURE_DEVOPS_PAT = "your-pat"
.\scripts\init-repo-remote.ps1

# 3. Verify variable names in Azure DevOps
# Go to: Pipelines > Library > Fabric-Deployment-test
# Check that variables are named: FABRIC_WORKSPACE_ID_TEST, SERVICE_PRINCIPAL_ID_TEST, etc.

# 4. Manually update if needed
az pipelines variable-group variable update --group-id <id> --name "FABRIC_WORKSPACE_ID_TEST" --value "<workspace-id>" --org <org> --project <project>
```

**Understanding Variable Naming:**

The pipeline loads **all three variable groups** (dev, test, prod) simultaneously. Without environment-specific names:
- Variables from different groups would have identical names
- Azure DevOps would use values from the last loaded group
- Test deployments would incorrectly target production workspace

With environment-specific naming:
- Each variable has unique name: `FABRIC_WORKSPACE_ID_DEV`, `FABRIC_WORKSPACE_ID_TEST`, `FABRIC_WORKSPACE_ID_PROD`
- Pipeline reads `DEPLOY_ENV` (set from branch name: dev/test/main → dev/test/prod)
- Script constructs correct variable name dynamically: `FABRIC_WORKSPACE_ID_{DEPLOY_ENV.upper()}`
- Each branch deploys to its correct workspace

**Prevention:**
- Run complete `terraform apply` after updating to environment-specific variables
- Run `init-repo-remote.ps1` to update pipeline YAML on all branches
- Verify variable names include environment suffix in Azure DevOps Library
- Don't manually rename variable groups
- Verify all three groups created successfully

### Issue: Multiple Workspace References in State

**Error Messages:**
```
Error: Resource already exists in state
Error: A resource with the ID "fabric_workspace.main" already exists
Error: Cannot add resource with duplicate address
```

**Problem:**
After upgrading from single-workspace to multi-workspace configuration, Terraform state contains conflicting resource addresses.

**Root Cause:**
Old state has `fabric_workspace.main` (single resource), but new configuration expects `fabric_workspace.main["dev"]`, `fabric_workspace.main["test"]`, `fabric_workspace.main["prod"]` (indexed resources).

**Solutions:**
```powershell
# Backup current state
terraform state pull > terraform-state-backup.json
Copy-Item terraform.tfstate terraform.tfstate.pre-migration

# List current workspace resources
terraform state list | Select-String "workspace"

# Option 1: Remove old single workspace and import new ones
terraform state rm fabric_workspace.main
terraform import 'fabric_workspace.main["dev"]' "<dev-workspace-id>"
terraform import 'fabric_workspace.main["test"]' "<test-workspace-id>"
terraform import 'fabric_workspace.main["prod"]' "<prod-workspace-id>"

# Option 2: Move existing workspace to dev (if keeping existing workspace)
terraform state mv fabric_workspace.main 'fabric_workspace.main["dev"]'
# Then import test and prod
terraform import 'fabric_workspace.main["test"]' "<test-workspace-id>"
terraform import 'fabric_workspace.main["prod"]' "<prod-workspace-id>"

# Verify migration
terraform state list | Select-String "workspace"

# Should show:
# fabric_workspace.main["dev"]
# fabric_workspace.main["test"]
# fabric_workspace.main["prod"]

# Validate configuration
terraform plan

# Apply any remaining changes
terraform apply
```

**Prevention:**
- Always backup state before major configuration changes
- Plan migration strategy when changing resource structures
- Test state modifications in non-production environments first

## 📊 Resource State Issues

### Issue: Resource Already Exists

**Error Messages:**
```
Error: A resource with the ID already exists
Error: Resource group already exists
```

**Solutions:**
```powershell
# Import existing resource into Terraform state
terraform import azurerm_resource_group.main /subscriptions/<sub-id>/resourceGroups/<rg-name>

# Or remove from Azure and let Terraform recreate
az group delete --name <resource-group-name> --yes --no-wait

# Check for naming conflicts
az resource list --name <resource-name> --query "[].{name:name, resourceGroup:resourceGroup, type:type}"
```

### Issue: State File Corruption

**Error Messages:**
```
Error: State file appears to be corrupt
Error: Failed to load state: invalid character
```

**Solutions:**
```powershell
# Backup current state
Copy-Item terraform.tfstate terraform.tfstate.backup

# Download state from backend
terraform state pull > terraform.tfstate.backup

# Re-initialize and restore
Remove-Item .terraform -Recurse -Force
terraform init -backend-config=backend.hcl

# If state is severely corrupted, consider manually recreating
# terraform import for each resource
```

## 🚨 Emergency Procedures

### Complete Reset

If everything is broken and you need to start fresh:

```powershell
# 1. Backup important configuration
Copy-Item terraform.tfvars terraform.tfvars.backup
Copy-Item backend.hcl backend.hcl.backup

# 2. Clean Terraform state
Remove-Item .terraform -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item terraform.tfstate* -Force -ErrorAction SilentlyContinue
Remove-Item .terraform.lock.hcl -Force -ErrorAction SilentlyContinue

# 3. Re-authenticate to Azure
az logout
az login
az account set --subscription <your-subscription-id>

# 4. Reinitialize from scratch
terraform init -backend-config=backend.hcl
terraform plan
```

### Partial Recovery

To recover specific resources:

```powershell
# Import individual resources
terraform import azurerm_resource_group.main <resource-id>
terraform import 'fabric_workspace.main["dev"]' <dev-workspace-id>
terraform import 'fabric_workspace.main["test"]' <test-workspace-id>
terraform import 'fabric_workspace.main["prod"]' <prod-workspace-id>
terraform import azuredevops_project.main <project-id>

# Verify imports worked
terraform plan
```

## 📞 Getting Help

### Microsoft Support Channels

- **Azure Support**: Azure Portal > Help + Support
- **Microsoft Fabric**: [Fabric Community](https://community.fabric.microsoft.com/)
- **Azure DevOps**: [DevOps Support](https://developercommunity.visualstudio.com/AzureDevOps)

### Community Resources

- **Terraform Azure Provider**: [GitHub Issues](https://github.com/hashicorp/terraform-provider-azurerm/issues)
- **Microsoft Fabric Provider**: [GitHub Issues](https://github.com/microsoft/terraform-provider-fabric/issues)
- **Stack Overflow**: Tag questions with `azure`, `terraform`, `microsoft-fabric`

### Collecting Debug Information

When reporting issues, collect this information:

```powershell
# System information
terraform version
az version
$PSVersionTable.PSVersion

# Configuration (sanitized)
terraform validate
terraform plan -no-color > debug-plan.txt

# Azure information
az account show
az account list-locations --query "[?displayName=='East US 2']"

# Error logs
$env:TF_LOG = "DEBUG"
$env:TF_LOG_PATH = "terraform-debug.log"
terraform plan
```

Remember to sanitize sensitive information before sharing debug output!