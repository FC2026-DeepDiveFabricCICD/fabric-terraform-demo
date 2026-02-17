# Microsoft Fabric Workspace and Azure DevOps Terraform Configuration
# This configuration sets up Microsoft Fabric workspace and Azure DevOps repository
# with OIDC authentication for secure, passwordless deployment

terraform {
  required_version = ">= 1.8, < 2.0"
  
  required_providers {
    fabric = {
      source  = "microsoft/fabric"
      version = "~> 1.7.0"
    }
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "~> 1.13.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.0"
    }
  }

  # Local state file - no remote backend required
  # For team collaboration, consider adding backend configuration later
}

# Azure Provider Configuration
provider "azurerm" {
  features {}
}

# Microsoft Fabric Provider Configuration
provider "fabric" {
  # Authentication via Azure CLI
  preview = true  # Required for fabric_workspace_git resource
}

# Azure DevOps Provider Configuration
provider "azuredevops" {
  org_service_url = "https://dev.azure.com/${var.azuredevops_org_name}"
}

# Azure AD Provider Configuration
provider "azuread" {
  # Authentication via Azure CLI
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Local values for consistent tagging and naming
locals {
  common_tags = {
    Environment   = var.environment
    Project      = var.project_name
    ManagedBy    = "Terraform"
    Owner        = var.owner_email
    CreatedDate  = timestamp()
  }
}