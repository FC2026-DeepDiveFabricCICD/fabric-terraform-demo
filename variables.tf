# Input Variables for Fabric Terraform DevOps Configuration
# These variables allow customization of the deployment for different environments

# Project and Environment Configuration
variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "Project name must be 2-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "environment" {
  description = "[DEPRECATED] Environment name - no longer used in multi-workspace setup. All environments (dev, test, prod) are created automatically. Kept for backward compatibility only."
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "owner_email" {
  description = "Email address of the project owner (for tagging and notifications)"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.owner_email))
    error_message = "Owner email must be a valid email address."
  }
}

# Azure Configuration
variable "azure_location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US 2"
}

variable "subscription_id" {
  description = "Azure subscription ID where resources will be deployed"
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "Subscription ID must be a valid GUID format."
  }
}

variable "tenant_id" {
  description = "Azure Active Directory tenant ID"
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.tenant_id))
    error_message = "Tenant ID must be a valid GUID format."
  }
}

# Microsoft Fabric Configuration
variable "fabric_capacity_id" {
  description = "ID of the Microsoft Fabric capacity (required for workspace creation)"
  type        = string
  validation {
    condition     = can(regex("^[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}$", var.fabric_capacity_id))
    error_message = "Fabric capacity ID must be a valid uppercase GUID format."
  }
}

variable "workspace_prefix" {
  description = "Prefix for Fabric workspace names. Three workspaces will be created: {prefix}-dev, {prefix}-test, {prefix}-prod"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,90}$", var.workspace_prefix))
    error_message = "Workspace prefix must be 1-90 characters using letters, numbers, underscores, and hyphens (no spaces to ensure valid workspace names)."
  }
}

variable "fabric_workspace_name" {
  description = "[DEPRECATED] Use workspace_prefix instead. This creates a single workspace name, but multi-workspace setup uses workspace_prefix for all three environments."
  type        = string
  default     = ""
  validation {
    condition     = var.fabric_workspace_name == "" || can(regex("^[a-zA-Z0-9 _-]{1,100}$", var.fabric_workspace_name))
    error_message = "Fabric workspace name must be 1-100 characters using letters, numbers, spaces, underscores, and hyphens."
  }
}

variable "fabric_workspace_description" {
  description = "Base description for Microsoft Fabric workspaces. Each workspace will append its environment suffix (Development, Testing, Production)"
  type        = string
  default     = "Fabric workspace for"
}

variable "environments" {
  description = "Map of environments to create workspaces for. Each environment defines workspace configuration including Git integration and branch mapping."
  type = map(object({
    workspace_suffix       = string
    enable_git_integration = bool
    git_branch_name        = string
    description_suffix     = string
    pr_min_reviewers       = number
  }))
  default = {
    dev = {
      workspace_suffix       = "dev"
      enable_git_integration = true
      git_branch_name        = "dev"
      description_suffix     = "Development"
      pr_min_reviewers       = 0  # No PR required for dev
    }
    test = {
      workspace_suffix       = "test"
      enable_git_integration = false
      git_branch_name        = "test"
      description_suffix     = "Testing"
      pr_min_reviewers       = 1  # 1 reviewer required for test
    }
    prod = {
      workspace_suffix       = "prod"
      enable_git_integration = false
      git_branch_name        = "main"
      description_suffix     = "Production"
      pr_min_reviewers       = 2  # 2 reviewers required for prod
    }
  }
}

variable "enable_dev_git_integration" {
  description = "Enable Git integration for dev workspace. Set to false on first deployment, then true after running init-repo-remote.ps1 and pushing fabric-content to dev branch."
  type        = bool
  default     = false
}

# Azure DevOps Configuration
variable "azuredevops_org_name" {
  description = "Azure DevOps organization name (e.g., 'myorg' for https://dev.azure.com/myorg)"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,50}$", var.azuredevops_org_name))
    error_message = "Azure DevOps organization name must be 1-50 characters using letters, numbers, and hyphens."
  }
}

variable "azuredevops_project_name" {
  description = "Azure DevOps project name to create"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9 _-]{1,64}$", var.azuredevops_project_name))
    error_message = "Azure DevOps project name must be 1-64 characters using letters, numbers, spaces, underscores, and hyphens."
  }
}

variable "azuredevops_project_description" {
  description = "Description of the Azure DevOps project"
  type        = string
  default     = "Microsoft Fabric workspace deployment project"
}

variable "azuredevops_repository_name" {
  description = "Name of the Azure DevOps repository to create"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,64}$", var.azuredevops_repository_name))
    error_message = "Repository name must be 1-64 characters using letters, numbers, dots, underscores, and hyphens."
  }
}

# Git Integration Configuration
variable "enable_git_integration" {
  description = "[DEPRECATED] Use environments map instead. Git integration is automatically enabled for dev workspace only in multi-workspace setup."
  type        = bool
  default     = false
}

variable "git_provider" {
  description = "Git provider for Fabric workspace integration (AzureDevOps or GitHub)"
  type        = string
  default     = "AzureDevOps"
  validation {
    condition     = contains(["AzureDevOps", "GitHub"], var.git_provider)
    error_message = "Git provider must be either 'AzureDevOps' or 'GitHub'."
  }
}

# Pipeline Configuration
variable "create_deployment_pipeline" {
  description = "Create Azure DevOps pipeline for Fabric content deployment"
  type        = bool
  default     = true
}

variable "pipeline_branch_name" {
  description = "[DEPRECATED] Use environments map instead. Pipeline now triggers on all branches (dev, test, main) and auto-detects target environment."
  type        = string
  default     = "main"
}

# Security and Access Configuration
variable "fabric_workspace_admin_users" {
  description = "List of user email addresses to grant admin access to the Fabric workspace"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for email in var.fabric_workspace_admin_users : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All admin user emails must be valid email addresses."
  }
}

variable "fabric_workspace_member_users" {
  description = "List of user email addresses to grant member access to the Fabric workspace"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for email in var.fabric_workspace_member_users : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All member user emails must be valid email addresses."
  }
}

# Resource Configuration
variable "enable_monitoring" {
  description = "Enable monitoring and logging for resources"
  type        = bool
  default     = true
}

variable "retention_days" {
  description = "Number of days to retain logs and backups"
  type        = number
  default     = 30
  validation {
    condition     = var.retention_days >= 7 && var.retention_days <= 730
    error_message = "Retention days must be between 7 and 730."
  }
}

# Cost Management
variable "auto_pause_enabled" {
  description = "Enable auto-pause for development environments to reduce costs"
  type        = bool
  default     = false
}

# Service Principal Configuration
variable "service_principal_name" {
  description = "Name of the service principal to create for Fabric access"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9 _-]{1,120}$", var.service_principal_name))
    error_message = "Service principal name must be 1-120 characters using letters, numbers, spaces, underscores, and hyphens."
  }
}

# Azure AD Group Configuration
variable "azure_ad_group_name" {
  description = "Name of the Azure AD group to add the service principal to"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9 _.-]{1,256}$", var.azure_ad_group_name))
    error_message = "Azure AD group name must be 1-256 characters using letters, numbers, spaces, underscores, periods, and hyphens."
  }
}

variable "create_azure_ad_group" {
  description = "Whether to create the Azure AD group if it doesn't exist"
  type        = bool
  default     = false
}