# Microsoft Fabric Terraform Demo

🚀 **Complete Infrastructure-as-Code solution for Microsoft Fabric workspace management with Azure DevOps CI/CD integration**

This project demonstrates enterprise-grade deployment of Microsoft Fabric workspaces using Terraform, with integrated Azure DevOps pipelines for content deployment and management. It implements security best practices with OIDC authentication and provides a production-ready foundation for Fabric workspace automation.

## 🎯 What This Project Provides

- **Three Microsoft Fabric Workspaces** created automatically: dev, test, and prod environments
- **Branch-Based Deployment Workflow** with automated Git sync and CI/CD pipelines
- **Azure DevOps Integration** with repository, branch policies, and deployment pipelines
- **Service Principal Management** for automated Fabric access across all environments
- **Smart Git Integration** - dev workspace syncs directly, test/prod deploy via pipelines
- **Security Best Practices** with Azure AD group management and PR-based approvals
- **Comprehensive Documentation** and troubleshooting guides
- **Sample Content** and deployment examples

## 📋 Prerequisites

**CRITICAL**: This project requires a **provisioned Microsoft Fabric Capacity** (not trial).

### Essential Requirements

- **Azure Subscription** with Contributor permissions
- **Microsoft Fabric Capacity** (F2+ recommended, trial NOT supported)
- **Azure DevOps Organization** with admin access and project creation rights
- **Local Tools**: Terraform 1.8+, Azure CLI, Git
- **Authentication**: Azure CLI logged in with appropriate permissions

### Required Permissions

The user or service principal running this deployment must have:

**Fabric Permissions:**
- Create workspaces
- Assign capacity to workspaces
- Manage workspace settings and Git integration
- Capacity Admin role on your Fabric capacity

**Azure DevOps Permissions:**
- Create projects in the organization
- Configure service connections
- Manage branch policies and repository settings

## 🚀 Step-by-Step Setup

### 1. Clone and Configure

```bash
# Clone the repository
git clone <repository-url>
cd fabric-terraform-demo

# Copy and configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values
# Key variables: workspace_prefix, fabric_capacity_id, azuredevops_org_name
```

### 2. Authenticate with Azure

```bash
# Login to Azure CLI
az login

# Set your subscription
az account set --subscription "<your-subscription-id>"

# Login to Azure DevOps (if using Azure DevOps CLI)
az extension add --name azure-devops
#az devops login
```

### 3. Initialize Terraform

```bash
# Initialize Terraform (uses local state)
terraform init
```

### 4. Plan and Deploy Infrastructure (Phase 1)

This is a **two-phase deployment** to avoid branch policy conflicts during repository initialization.

**Important**: Set `enable_dev_git_integration = false` in your `terraform.tfvars` for the first deployment.

```bash
# Phase 1: Deploy infrastructure without branch policies
# Creates: 3 workspaces, Azure DevOps project, empty repository, pipeline
# Does NOT create: Git integration, branch policies (to allow init script to run)
terraform plan
terraform apply
```

This creates the infrastructure without branch policies or Git integration enabled.

### 5. Initialize the Repository

After the first `terraform apply`, initialize the repository with branches and fabric-content folder:

```powershell
# Set your Azure DevOps PAT (Code Read & Write scope required)
$env:AZURE_DEVOPS_PAT = "your-pat-here"

# Run the initialization script (creates main/dev/test branches remotely)
.\scripts\init-repo-remote.ps1
```

The script is **idempotent** and will:
- Create initial commit with README, .gitignore, and folder structure
- Create `main`, `dev`, and `test` branches
- Ensure `fabric-content` folder exists on all branches
- Set `main` as the default branch
- Skip steps that are already completed if run multiple times

**Why two phases?** Branch policies require PRs for changes to main/test branches. The init script needs to push directly to these branches to set them up. By deferring branch policy creation to Phase 2, the init script can complete successfully.

**What init-repo-remote.ps1 does:**
- Creates `main`, `dev`, and `test` branches via Azure DevOps REST API
- Ensures `fabric-content` folder exists on all branches
- Adds README.md, .gitignore, and complete pipeline YAML
- Sets `main` as the default branch
- Idempotent - safe to run multiple times

**Script configuration:**
The script reads from `terraform.tfvars`:
- `azuredevops_org_name` - Your Azure DevOps organization
- `azuredevops_project_name` - Project name
- `azuredevops_repository_name` - Repository name

### 6. Enable Git Integration and Branch Policies (Phase 2)

Now enable Git sync for the dev workspace and apply branch policies:

```bash
# Update terraform.tfvars: set enable_dev_git_integration = true

# Phase 2: Enable Git sync and branch policies
# Creates: Git connection, Git workspace integration, branch policies
terraform apply
```

After Phase 2 completes:
- ✅ Dev workspace syncs directly with dev branch (no PR required)
- ✅ Test branch requires 1 reviewer for PRs + build validation
- ✅ Main branch requires 2 reviewers for PRs + build validation

### 7. Verify Deployment

```bash
# Get important URLs and information
terraform output fabric_workspace_url
terraform output azuredevops_project_url
terraform output service_principal_application_id
```

After successful deployment, you'll have:
- ✅ Three Microsoft Fabric workspaces (dev, test, prod) ready to use
- ✅ Service principal created and added to Azure AD group
- ✅ Azure DevOps project with repository and pipelines
- ✅ Dev workspace with Git integration configured
- ✅ Test/prod workspaces ready for CI/CD deployments
- ✅ Branch protection policies enforcing PR reviews (test: 1 reviewer, main: 2 reviewers)

## 📁 Project Structure

```
fabric-terraform-demo/
├── 🏗️  Infrastructure Configuration
│   ├── main.tf                    # Provider configuration
│   ├── variables.tf               # Input variables with validation
│   ├── outputs.tf                 # Deployment outputs and URLs
│   ├── fabric-workspace.tf        # Fabric workspace resources
│   ├── azure-devops.tf            # DevOps project and pipeline setup
│   └── service-principal.tf       # Service principal management
│
├── 📊 Fabric Content (sample)
│   └── fabric-content/
│       └── SampleModel.pbip       # Sample Power BI project
│
├── � Pipelines
│   └── pipelines/
│       └── fabric-deploy.yaml     # Multi-workspace CI/CD pipeline (fabric_cicd inline)
│
├── 🔧 Scripts
│   └── scripts/
│       └── init-repo-remote.ps1   # Initialize Azure DevOps repo with branches
│
├── 📚 Configuration
│   └── terraform.tfvars.example   # Environment configuration template
│
└── 📖 Documentation
    ├── docs/
    │   ├── prerequisites.md       # Complete setup requirements
    │   └── troubleshooting.md     # Common issues and solutions
    └── README.md                  # This file
```

## 🔧 Configuration

### Required Variables (terraform.tfvars)

Create your `terraform.tfvars` file with the following configuration:

```hcl
# Project Configuration
project_name    = "fabric-demo"
workspace_prefix = "MyCompany"  # Creates: MyCompany-dev, MyCompany-test, MyCompany-prod
owner_email     = "your.email@company.com"

# Azure Configuration
subscription_id = "your-subscription-id"  # Get with: az account show --query id -o tsv
tenant_id       = "your-tenant-id"        # Get with: az account show --query tenantId -o tsv
azure_location  = "East US 2"

# Fabric Configuration
fabric_capacity_id = "YOUR-FABRIC-CAPACITY-ID"  # From Fabric Admin Portal

# Azure DevOps Configuration
azuredevops_org_name     = "your-devops-org"  # From https://dev.azure.com/YOUR-ORG
azuredevops_project_name = "Fabric Demo Project"

# Service Principal Configuration
service_principal_name = "sp-fabric-demo"
azure_ad_group_name    = "Fabric-Demo-ServicePrincipals"
create_azure_ad_group  = true  # false if group already exists

# Optional: Override default environment configurations
# environments = {
#   dev = {
#     display_name     = "Custom Dev Name"
#     description      = "Development workspace"
#     enable_git_integration = true
#     pipeline_branch  = "dev"
#   }
#   test = {
#     display_name     = "Custom Test Name"
#     description      = "Testing workspace"
#     enable_git_integration = false
#     pipeline_branch  = "test"
#   }
#   prod = {
#     display_name     = "Custom Prod Name"
#     description      = "Production workspace"
#     enable_git_integration = false
#     pipeline_branch  = "main"
#   }
# }
```

### Deprecated Variables

The following variables are **no longer used** in the multi-workspace architecture:
- `environment` - All three environments are created automatically
- `fabric_workspace_name` - Use `workspace_prefix` instead
- `enable_git_integration` - Dev workspace has Git sync by default
- `pipeline_branch_name` - Each environment has its own branch

### Backend Configuration (Optional)

By default, Terraform uses local state. For team collaboration, you can add remote state later:

```hcl
# Add to main.tf if needed for team usage
backend "azurerm" {
  storage_account_name = "tfstateYOURUNIQUEID"
  container_name       = "tfstate"
  key                  = "fabric-demo.tfstate"
  resource_group_name  = "rg-terraform-state"
}
```

See [terraform.tfvars.example](terraform.tfvars.example) for complete configuration options.

## � Manual Setup Order (Before Terraform)

If you prefer to set up resources manually or need to understand the deployment order:

### 1. Azure Setup (Optional)
```bash
# Only needed if you want remote state storage later
# az group create --name "rg-terraform-state" --location "East US 2"
# az storage account create --name "tfstateUNIQUEID" --resource-group "rg-terraform-state"
```

### 2. Azure DevOps Setup (Optional - Terraform will create these)
```bash
# Create Azure DevOps project (Terraform will do this)
az devops project create --name "Fabric Demo Project" --org "https://dev.azure.com/YOUR-ORG"

# The following will be created by Terraform:
# - Git repository
# - Variable groups
# - Build pipelines
# - Service connections
```

### 3. Azure AD Groups (Optional - Terraform can create)
```bash
# Create Azure AD group for service principals (or let Terraform create it)
az ad group create --display-name "Fabric-Demo-ServicePrincipals" --mail-nickname "FabricDemoSPs"
```

### 4. Run Terraform
```bash
# Terraform will create everything:
# - Service principal with proper Fabric permissions
# - Add service principal to Azure AD group
# - Microsoft Fabric workspace
# - Azure DevOps repository and pipeline
```

## �🚀 Deployment Workflows

### Development Environment

```bash
# Quick development deployment
terraform plan -var="environment=dev"
terraform apply -auto-approve

# Add your content to fabric-content/ directory
# Commit and push to trigger pipeline
git add fabric-content/
git commit -m "Add: New analysis notebook"
git push origin main
```

### Production Environment

```bash
# Production deployment with manual approval
terraform plan -var="environment=prod"
# Review the plan carefully
terraform apply  # Manual approval required
```

### Managing Different Environments

```bash
# Use workspace-specific tfvars files
terraform plan -var-file="environments/dev.tfvars"
terraform plan -var-file="environments/prod.tfvars"

# Or use Terraform workspaces
terraform workspace new dev
terraform workspace new prod
terraform workspace select dev
```

## 🔀 Branching Strategy

The project implements a **promote-through-environments** workflow:

```
dev (Direct Git Sync)    test (Pipeline)         main (Pipeline)
     ↓                        ↓                        ↓
  Dev Workspace          Test Workspace          Prod Workspace
     │                        │                        │
     └─────── PR (1 rev) ─────┴────── PR (2 rev) ─────┘
```

### Development Process

1. **Develop in dev workspace**:
   - Work directly in the dev Fabric workspace
   - Commit changes to `dev` branch
   - Git sync automatically updates dev workspace

2. **Promote to test**:
   - Create PR: `dev` → `test`
   - Requires 1 reviewer approval
   - After merge, pipeline deploys to test workspace
   - Validate changes in test environment

3. **Release to production**:
   - Create PR: `test` → `main`
   - Requires 2 reviewers approval
   - After merge, pipeline deploys to prod workspace
   - Production deployment complete

### Branch Policies

Terraform automatically configures:
- **dev branch**: No restrictions (direct commits allowed)
- **test branch**: Requires 1 reviewer for PRs
- **main branch**: Requires 2 reviewers for PRs

### CI/CD Pipeline Details

The Azure DevOps pipeline (`pipelines/fabric-deploy.yaml`) automatically deploys Fabric items using the `fabric_cicd` Python library:

**Pipeline Stages:**
1. **DetectEnvironment**: Maps branch name to target environment
   - `dev` branch → dev environment
   - `test` branch → test environment
   - `main` branch → prod environment

2. **DeployFabric**: Executes deployment
   - Loads all three variable groups (Fabric-Deployment-dev, Fabric-Deployment-test, Fabric-Deployment-prod)
   - Uses environment-specific variable names to prevent conflicts (e.g., `FABRIC_WORKSPACE_ID_TEST`)
   - Deployment script reads `DEPLOY_ENV` and constructs the correct variable name dynamically
   - Authenticates with service principal using environment-specific credentials
   - Publishes all items from fabric-content/ to the correct workspace
   - Removes orphaned items

**Variable Group Loading Strategy:**

All three variable groups are loaded simultaneously with environment-specific variable names:
- **Problem**: Loading groups with identical variable names causes the last group to override previous values
- **Solution**: Each variable is suffixed with its environment (e.g., `FABRIC_WORKSPACE_ID_DEV`, `FABRIC_WORKSPACE_ID_TEST`, `FABRIC_WORKSPACE_ID_PROD`)
- **Benefit**: Simplifies pipeline authorization (one-time setup) and prevents cross-environment deployments

**Supported Item Types:**
- Semantic Models (`.pbip` datasets)
- Reports (`.pbir` Power BI reports)
- Notebooks
- Data Pipelines
- Environments
- Lakehouses & Warehouses

**Variable Groups (Auto-Created by Terraform):**
- `Fabric-Deployment-dev` - Dev workspace credentials
- `Fabric-Deployment-test` - Test workspace credentials
- `Fabric-Deployment-prod` - Prod workspace credentials

**Environment-Specific Variable Naming:**

To prevent variable conflicts when multiple groups are loaded, each variable is suffixed with the environment name:

**Dev Environment Variables:**
- `FABRIC_WORKSPACE_ID_DEV` - Dev workspace GUID
- `SERVICE_PRINCIPAL_ID_DEV` - Azure AD app client ID
- `SERVICE_PRINCIPAL_SECRET_DEV` - Client secret (marked secret)
- `AZURE_TENANT_ID_DEV` - Azure AD tenant ID

**Test Environment Variables:**
- `FABRIC_WORKSPACE_ID_TEST` - Test workspace GUID
- `SERVICE_PRINCIPAL_ID_TEST` - Azure AD app client ID
- `SERVICE_PRINCIPAL_SECRET_TEST` - Client secret (marked secret)
- `AZURE_TENANT_ID_TEST` - Azure AD tenant ID

**Prod Environment Variables:**
- `FABRIC_WORKSPACE_ID_PROD` - Prod workspace GUID
- `SERVICE_PRINCIPAL_ID_PROD` - Azure AD app client ID
- `SERVICE_PRINCIPAL_SECRET_PROD` - Client secret (marked secret)
- `AZURE_TENANT_ID_PROD` - Azure AD tenant ID

**Why Environment-Specific Names?**

The pipeline loads all three variable groups simultaneously to simplify authorization. Without environment-specific naming, variables from the last loaded group would override previous ones, causing deployments to target the wrong workspace. The deployment script reads `DEPLOY_ENV` (set based on branch name) and dynamically constructs the correct variable name (e.g., `FABRIC_WORKSPACE_ID_TEST` for test branch).

**Manually triggering pipeline:**
```bash
# Navigate to Azure DevOps Pipelines
# Select "Fabric-Content-Deploy" pipeline
# Click "Run pipeline"
# Select branch: dev, test, or main
```

## 🔐 Security Features

- **Service Principal Management**: Automated creation of service principals for Fabric access
- **Azure AD Group Integration**: Automatic assignment of service principals to specified Azure AD groups
- **Credential Management**: Service principal credentials available through Terraform outputs
- **RBAC Configuration**: Least-privilege access patterns
- **Audit Logging**: Comprehensive deployment and access tracking

### Service Principal Configuration

The deployment automatically creates a service principal for Microsoft Fabric access:

- **Service Principal**: Created with appropriate Fabric permissions
- **Azure AD Group**: Service principal is added to the specified group for centralized management  
- **Credential Access**: Client credentials available through Terraform outputs
- **Workspace Access**: Service principal granted Admin role on each Fabric workspace

**Required Manual Setup** (before running Terraform):
1. Grant the service principal **Capacity Admin** role on your Fabric capacity
2. Ensure the service principal has **Fabric Administrator** role in Microsoft 365 (if assigning licenses)
3. Add the service principal as a **Capacity Admin** in the Fabric Admin Portal

See [docs/prerequisites.md](docs/prerequisites.md#service-principal-permissions-required) for detailed permission requirements.

## 📊 Monitoring and Operations

### Deployment Outputs

After deployment, access your resources:

- **Fabric Workspaces**: 
  - Dev: `terraform output fabric_workspace_dev_url`
  - Test: `terraform output fabric_workspace_test_url`
  - Prod: `terraform output fabric_workspace_prod_url`
- **Azure DevOps Project**: Retrieved from `terraform output azuredevops_project_url`  
- **Repository**: Retrieved from `terraform output azuredevops_repository_url`
- **Pipeline**: Retrieved from `terraform output deployment_pipeline_url`

### Health Checks

```bash
# Validate current deployment
terraform plan

# Check pipeline status
az pipelines runs list --organization <org> --project <project>

# Get service principal information
terraform output service_principal_application_id
terraform output azure_ad_group_id

# Monitor Fabric workspaces
terraform output fabric_workspace_dev_url
terraform output fabric_workspace_test_url
terraform output fabric_workspace_prod_url
```

## 🔧 Customization

### Modifying Environment Configurations

By default, the project creates three workspaces: dev, test, and prod. To customize environment names, descriptions, or settings, use the `environments` variable in `terraform.tfvars`:

```hcl
environments = {
  dev = {
    display_name           = "Engineering Development"
    description            = "Development workspace for engineering team"
    enable_git_integration = true
    pipeline_branch        = "dev"
  }
  test = {
    display_name           = "QA Testing Environment"
    description            = "Quality assurance testing workspace"
    enable_git_integration = false
    pipeline_branch        = "test"
  }
  prod = {
    display_name           = "Production"
    description            = "Production workspace - controlled access"
    enable_git_integration = false
    pipeline_branch        = "main"
  }
}
```

### Adding Additional Environments

To add a fourth environment (e.g., staging):

1. **Update the environments map** in `terraform.tfvars`:
   ```hcl
   environments = {
     dev     = { ... }
     staging = {
       display_name           = "Staging Environment"
       description            = "Pre-production staging"
       enable_git_integration = false
       pipeline_branch        = "staging"
     }
     test    = { ... }
     prod    = { ... }
   }
   ```

2. **Create the staging branch** in Azure DevOps

3. **Add branch policy configuration** if needed

4. **Deploy**:
   ```bash
   terraform apply
   ```

### Adding Custom Content Types

1. **Create content structure**:
   ```
   fabric-content/
   ├── your-content-type/
   │   ├── sample-artifact.json
   │   └── README.md
   ```

2. **Update pipeline**: Modify [pipelines/fabric-deploy.yaml](pipelines/fabric-deploy.yaml)

3. **Add deployment logic**: Extend pipeline steps for your content type

## 🆘 Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| **Terraform version too old** | Update Terraform: `terraform version` |
| **Fabric capacity not found** | Verify capacity ID in Fabric Admin Portal |
| **Azure auth failed** | `az login --tenant <tenant-id>` |
| **DevOps access denied** | Check Azure DevOps organization permissions |
| **Service principal permissions** | Verify Azure AD and Fabric permissions |

### Useful Commands

```bash
# Check Terraform configuration
terraform validate
terraform fmt -check

# Debug Terraform with detailed logging
TF_LOG=DEBUG terraform plan

# Test Azure connectivity
az account show
az devops project list --organization "https://dev.azure.com/YOUR-ORG"

# Verify Fabric capacity
az account get-access-token --resource "https://api.fabric.microsoft.com/"

# Check service principal
az ad sp show --id $(terraform output -raw service_principal_application_id)
```

See [Troubleshooting Guide](docs/troubleshooting.md) for comprehensive solutions.

## 🚀 Complete Setup Guide

### Step-by-Step Instructions (No PowerShell Required)

1. **Prerequisites & Authentication**
   ```bash
   # Install required tools
   # - Terraform 1.8+
   # - Azure CLI
   # - Git
   
   # Login to Azure
   az login
   az account set --subscription "YOUR-SUBSCRIPTION-ID"
   
   # Login to Azure DevOps
   az extension add --name azure-devops
   az devops login --organization "https://dev.azure.com/YOUR-ORG"
   ```

2. **Clone and Configure**
   ```bash
   git clone <repository-url>
   cd fabric-terraform-demo
   
   # Configure variables (uses local state by default)
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

3. **Initialize and Deploy**
   ```bash
   # Initialize Terraform
   terraform init
   
   # Plan deployment
   terraform plan
   
   # Deploy infrastructure
   terraform apply
   ```

4. **Verify and Access**
   ```bash
   # Get workspace URLs for all environments
   terraform output fabric_workspace_dev_url
   terraform output fabric_workspace_test_url
   terraform output fabric_workspace_prod_url
   terraform output azuredevops_project_url
   
   # Get service principal info
   terraform output service_principal_application_id
   terraform output azure_ad_group_name
   ```

That's it! No PowerShell scripts needed - everything is managed through Terraform configuration files.

## 📚 Documentation

- **[Prerequisites Guide](docs/prerequisites.md)**: Complete setup requirements
- **[Troubleshooting Guide](docs/troubleshooting.md)**: Common issues and solutions
- **[Terraform Variables](terraform.tfvars.example)**: Configuration reference
- **[Pipeline Configuration](pipelines/fabric-deploy.yaml)**: CI/CD setup

## 🤝 Contributing

Contributions are welcome! Please:

1. **Fork the repository** and create a feature branch
2. **Test your changes** with `terraform validate` and `terraform plan`
3. **Update documentation** for any new features
4. **Submit a pull request** with clear description of changes

## 🏷️ Tags

`#MicrosoftFabric` `#Terraform` `#AzureDevOps` `#InfrastructureAsCode` `#CICD` `#PowerBI` `#DataEngineering` `#Azure`

---

**Made with ❤️ by the Fabric Community** | **Enterprise-Ready** | **Production-Tested**