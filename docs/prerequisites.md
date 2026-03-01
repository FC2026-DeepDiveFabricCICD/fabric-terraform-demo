# Prerequisites for Microsoft Fabric Terraform Setup

This document outlines all prerequisites required to successfully deploy Microsoft Fabric workspaces with Azure DevOps integration using Terraform.

## 📋 Quick Overview

You need:

1. **Azure Subscription** with Contributor permissions
2. **Microsoft Fabric Capacity** (F2+ recommended, trial NOT supported)
3. **Azure DevOps Organization** with admin access
4. **Local Tools**: Terraform 1.8+, Azure CLI, PowerShell, Git
5. **Service Principal** with proper permissions (created automatically by Terraform)

## 🔧 Local Development Tools

### Install Required Tools

```powershell
# Install via Windows Package Manager (winget)
winget install Hashicorp.Terraform
winget install Microsoft.AzureCLI  
winget install Git.Git
winget install Microsoft.PowerShell
```

### Minimum Versions

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| Terraform | 1.8.0 | Required for Microsoft Fabric provider |
| Azure CLI | 2.50.0 | Authentication and resource management |
| PowerShell | 7.0 | Repository initialization script |
| Git | 2.30 | Version control (optional for local use) |

### Verify Installation

```powershell
terraform version  # Should be 1.8.0+
az --version       # Should be 2.50.0+
pwsh --version     # Should be 7.0+
```

## ☁️ Azure Subscription Requirements

### Required Azure Permissions

Your Azure account needs these roles:

| Role | Scope | Purpose |
|------|-------|---------|
| **Contributor** | Subscription | Create and manage Azure resources |
| **User Access Administrator** | Subscription | Assign roles to service principals |

### Azure AD Permissions

To create service principals and app registrations:

- **Application Developer** role (minimum)
- **Application Administrator** role (recommended for full control)

### Authentication

Login to Azure CLI before running Terraform:

```powershell
az login
az account set --subscription "<your-subscription-id>"
az account show  # Verify correct subscription
```

## 🏗️ Microsoft Fabric Capacity

### Critical Requirements

**⚠️ IMPORTANT**: 
- Microsoft Fabric **trial capacity is NOT supported** by the Terraform provider
- This configuration creates **THREE workspaces** (dev, test, prod) on your capacity
- Minimum **F2 SKU** required, **F4+ recommended** for multi-workspace production use

### What You Need

1. **Provisioned Fabric Capacity** (not trial or paused)
2. **Capacity Admin** role for your user account
3. **Power BI Pro license** (minimum) for workspace access
4. **Fabric capacity ID** (GUID format)

### How to Get Your Capacity ID

1. Navigate to Azure Portal:
   ```
   https://portal.azure.com/#browse/Microsoft.Fabric%2Fcapacities
   ```

2. Select your Fabric capacity

3. Copy the **Resource ID** or **Capacity ID** (GUID format, looks like: `00000000-0000-0000-0000-000000000000`)

### Required Fabric Permissions

The user or service principal running Terraform **must have**:

| Permission | Purpose |
|------------|---------|
| **Create Workspaces** | Provision dev, test, and prod workspaces |
| **Assign Capacity** | Attach workspaces to your Fabric capacity |
| **Manage Workspace Settings** | Configure Git integration |
| **Capacity Admin Role** | Full capacity and workspace management |

**How to grant permissions:**

1. Go to Fabric Admin Portal: `https://app.powerbi.com/admin-portal`
2. Navigate to **Capacity settings** → Select your capacity → **Permissions**
3. Add your user account or service principal as **Admin**
4. If using service principal: Grant **Fabric Administrator** role in Microsoft 365 admin center

## 🚀 Azure DevOps Organization

### What You Need

- **Azure DevOps organization** (create at `https://dev.azure.com`)
- **Organization owner** or **Project Collection Administrator** role
- **Basic license** (Stakeholder licenses have limitations)
- Permission to:
  - Create projects
  - Configure repositories
  - Manage service connections
  - Set branch policies

### Verify Your Access

1. Navigate to: `https://dev.azure.com/<your-org-name>`
2. Go to **Organization Settings** → **Users**
3. Verify your role includes project creation rights
4. Ensure **Azure Repos** and **Azure Pipelines** are enabled

## 🔐 Service Principal Authentication

### How It Works

Terraform automatically creates a service principal with client secret authentication for:
- Fabric workspace management
- Azure DevOps Git integration
- Pipeline deployment automation

**Note**: This project uses **client secret authentication**, not OIDC/passwordless authentication.

### Required Permissions for Service Principal

The service principal created by Terraform needs these permissions (granted manually):

**Before running Terraform:**
1. **Fabric Capacity Admin** - Add to your capacity in Fabric Admin Portal
2. **Fabric Administrator** (optional) - Only if managing user licenses

**Automatically granted by Terraform:**
- Azure AD application registration
- Azure subscription Contributor role (for resources)
- Workspace Admin role on each Fabric workspace
- Azure DevOps project access for Git integration

### Setting Up Capacity Admin Access

**Critical Step**: After Terraform creates the service principal, you must manually add it to your Fabric capacity:

1. Run `terraform apply` (it will create the service principal)
2. Note the service principal's client ID from outputs
3. Go to Fabric Admin Portal: `https://app.powerbi.com/admin-portal`
4. Navigate to **Capacity settings** → Select your capacity → **Permissions**
5. Add the service principal by its client ID or application name
6. Grant **Admin** role
7. Run `terraform apply` again to complete workspace configuration

## 📦 Configuration Setup

### Create terraform.tfvars

Copy the example file and configure your settings:

```powershell
copy terraform.tfvars.example terraform.tfvars
```

### Required Configuration Values

Edit `terraform.tfvars` with your specific values:

```hcl
# Project Configuration
project_name = "fabric-demo"
owner_email  = "your.email@company.com"

# Azure Configuration
azure_location    = "East US 2"
subscription_id   = "00000000-0000-0000-0000-000000000000"  # Your subscription ID
tenant_id        = "00000000-0000-0000-0000-000000000000"  # Your tenant ID

# Microsoft Fabric Multi-Workspace Configuration
workspace_prefix             = "FabricDemo"  # Creates: FabricDemo-dev, FabricDemo-test, FabricDemo-prod
fabric_capacity_id          = "00000000-0000-0000-0000-000000000000"  # Your Fabric capacity ID
fabric_workspace_description = "Fabric workspace for"

# Azure DevOps Configuration
azuredevops_org_url         = "https://dev.azure.com/your-org-name"
azuredevops_project_name    = "Fabric-Terraform-Demo"
azuredevops_repo_name       = "fabric-content"

# Service Principal Configuration
fabric_sp_name = "fabric-deployment-sp"
# Optional: Specify existing Azure AD group for service principal membership
# azure_ad_group_name = "Fabric-Service-Principals"

# Phased Git Integration Deployment (recommended for new projects)
enable_dev_git_integration = false  # Set to true after repository is initialized
```

### State Management

By default, Terraform uses **local state** (terraform.tfstate file in your project directory).

**For production or team environments:**
- Configure remote state backend (Azure Storage, Terraform Cloud, etc.) after initial setup
- See [Terraform backend documentation](https://developer.hashicorp.com/terraform/language/settings/backends/configuration) for options

### Security Note

**⚠️ IMPORTANT**: Never commit `terraform.tfvars` to version control!
- It contains sensitive information (subscription IDs, tenant IDs)
- It's already in `.gitignore`
- Use Azure Key Vault or similar for production secrets

## 🔍 Pre-Deployment Checklist

Before running `terraform apply`:

- [ ] All tools installed (Terraform 1.8+, Azure CLI, PowerShell)
- [ ] Azure CLI authenticated (`az login` and `az account show`)
- [ ] Fabric capacity provisioned (F2+ SKU, not trial)
- [ ] Your account has **Capacity Admin** role on Fabric capacity
- [ ] Azure DevOps organization accessible with admin rights
- [ ] `terraform.tfvars` created and configured with all required values
- [ ] Terraform initialized successfully (`terraform init`)

### Quick Verification Commands

```powershell
# Verify tools
terraform version
az --version
pwsh --version

# Verify Azure authentication
az login
az account show

# Verify Azure DevOps access
az devops project list --org https://dev.azure.com/<your-org-name>

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Preview changes
terraform plan
```

## 🚀 Deployment Steps

### 1. Initial Deployment (without Git integration)

```powershell
# Ensure enable_dev_git_integration = false in terraform.tfvars
terraform apply
```

This creates:
- Three Fabric workspaces (dev, test, prod)
- Azure DevOps project
- Service principal with credentials
- Azure DevOps service connection (placeholder, before repo exists)

### 2. Initialize Repository

After Terraform completes, initialize the Azure DevOps repository:

```powershell
.\scripts\init-repo-remote.ps1
```

This creates:
- main, dev, and test branches
- fabric-content folder structure
- Pipeline YAML configuration
- Branch policies (PR requirements)

### 3. Enable Git Integration

After repository is initialized:

1. Edit `terraform.tfvars`:
   ```hcl
   enable_dev_git_integration = true
   ```

2. Apply changes:
   ```powershell
   terraform apply
   ```

This connects the dev workspace to the dev branch with automatic synchronization.

### 4. Verify Deployment

```powershell
# View workspace URLs
terraform output fabric_workspace_dev_url
terraform output fabric_workspace_test_url
terraform output fabric_workspace_prod_url

# View Azure DevOps resources
terraform output azuredevops_project_url
terraform output azuredevops_repository_url
```

## 🆘 Common Issues

### Terraform version too old
```
Error: terraform version < 1.8.0
Solution: winget upgrade Hashicorp.Terraform
```

### Azure authentication failed
```
Error: az account show returns empty
Solution: az login --tenant <tenant-id>
```

### Fabric capacity not found
```
Error: capacity ID invalid or inaccessible
Solution: Verify capacity exists, check GUID format, ensure you have Capacity Admin role
```

### Azure DevOps access denied
```
Error: cannot create project or repository
Solution: Verify organization permissions, ensure Basic license (not Stakeholder)
```

### Service principal lacks Fabric permissions
```
Error: workspace creation fails with authorization error
Solution: 
1. Get service principal client ID: terraform output fabric_sp_client_id
2. Add to Fabric capacity as Admin in Fabric Admin Portal
3. Run terraform apply again
```

## 📚 Additional Resources

- [Microsoft Fabric Documentation](https://learn.microsoft.com/fabric/)
- [Fabric Terraform Provider](https://registry.terraform.io/providers/microsoft/fabric/latest/docs)
- [Azure DevOps Documentation](https://learn.microsoft.com/azure/devops/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## 🎯 Next Steps

After successful deployment:

1. **Verify workspaces** - Open Fabric portal and confirm three workspaces exist
2. **Check Git integration** - Dev workspace should show Git sync status
3. **Add Fabric content** - Copy your `.pbip` files to `fabric-content/` folder
4. **Commit changes** - Push to dev branch to trigger automatic sync
5. **Test pipeline** - Create PR from dev to test branch to trigger deployment pipeline

---

For detailed architecture and workflow information, see the main [README.md](../README.md).