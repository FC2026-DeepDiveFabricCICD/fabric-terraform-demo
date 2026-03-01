# Output Values from Terraform Configuration
# These outputs provide important information after deployment
# Multi-workspace architecture: outputs are maps with keys dev, test, prod

# Microsoft Fabric Outputs (Maps for all workspaces)
output "fabric_workspace_ids" {
  description = "IDs of the created Microsoft Fabric workspaces (map: dev, test, prod)"
  value       = { for k, v in fabric_workspace.main : k => v.id }
}

output "fabric_workspace_names" {
  description = "Names of the created Microsoft Fabric workspaces (map: dev, test, prod)"
  value       = { for k, v in fabric_workspace.main : k => v.display_name }
}

output "fabric_workspace_urls" {
  description = "URLs to access the Microsoft Fabric workspaces (map: dev, test, prod)"
  value       = { for k, v in fabric_workspace.main : k => "https://app.fabric.microsoft.com/home?workspaceObjectId=${v.id}" }
}

output "fabric_git_connection_id" {
  description = "ID of the Fabric Git connection (dev workspace only)"
  value       = length(fabric_connection.azdo_git) > 0 ? { for k, v in fabric_connection.azdo_git : k => v.id } : null
}

# Azure DevOps Outputs
output "azuredevops_project_id" {
  description = "ID of the created Azure DevOps project"
  value       = azuredevops_project.main.id
}

output "azuredevops_project_url" {
  description = "URL to the created Azure DevOps project"
  value       = "https://dev.azure.com/${var.azuredevops_org_name}/${azuredevops_project.main.name}"
}

output "azuredevops_repository_id" {
  description = "ID of the created Azure DevOps repository"
  value       = azuredevops_git_repository.main.id
}

output "azuredevops_repository_url" {
  description = "URL to the created Azure DevOps repository"
  value       = azuredevops_git_repository.main.web_url
}

output "azuredevops_repository_clone_url" {
  description = "Clone URL for the Azure DevOps repository"
  value       = azuredevops_git_repository.main.remote_url
  sensitive   = true
}

# Pipeline Outputs
output "deployment_pipeline_id" {
  description = "ID of the deployment pipeline (if created)"
  value       = var.create_deployment_pipeline ? azuredevops_build_definition.fabric_deploy[0].id : null
}

output "deployment_pipeline_url" {
  description = "URL to the deployment pipeline (if created)"
  value       = var.create_deployment_pipeline ? "https://dev.azure.com/${var.azuredevops_org_name}/${azuredevops_project.main.name}/_build?definitionId=${azuredevops_build_definition.fabric_deploy[0].id}" : null
}

# Variable Group Outputs
output "variable_group_ids" {
  description = "IDs of the variable groups (map: dev, test, prod) if created"
  value       = var.create_deployment_pipeline ? { for k, v in azuredevops_variable_group.fabric_deployment : k => v.id } : null
}

output "variable_group_names" {
  description = "Names of the variable groups (map: dev, test, prod) if created"
  value       = var.create_deployment_pipeline ? { for k, v in azuredevops_variable_group.fabric_deployment : k => v.name } : null
}

# Service Principal Outputs
output "service_principal_application_id" {
  description = "Application (Client) ID of the service principal"
  value       = azuread_application.fabric_sp.client_id
  sensitive   = true
}

output "service_principal_object_id" {
  description = "Object ID of the service principal"
  value       = azuread_service_principal.fabric_sp.object_id
  sensitive   = true
}

output "service_principal_display_name" {
  description = "Display name of the service principal"
  value       = azuread_service_principal.fabric_sp.display_name
}

output "azure_ad_group_id" {
  description = "Object ID of the Azure AD group"
  value       = local.azure_ad_group_id
  sensitive   = true
}

output "azure_ad_group_name" {
  description = "Name of the Azure AD group"
  value       = var.azure_ad_group_name
}

# Service Connection Outputs
output "service_connection_id" {
  description = "ID of the Azure service connection (if created)"
  value       = var.create_deployment_pipeline ? azuredevops_serviceendpoint_azurerm.fabric[0].id : null
}

output "service_connection_name" {
  description = "Name of the Azure service connection (if created)"
  value       = var.create_deployment_pipeline ? azuredevops_serviceendpoint_azurerm.fabric[0].service_endpoint_name : null
}

# Environment and Configuration Outputs
output "environments" {
  description = "Map of configured environments (dev, test, prod)"
  value       = { for k, v in var.environments : k => v.description_suffix }
}

output "workspace_prefix" {
  description = "Prefix used for workspace names"
  value       = var.workspace_prefix
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "azure_location" {
  description = "Azure region where resources are deployed"
  value       = var.azure_location
}

# Authentication Configuration Outputs
output "tenant_id" {
  description = "Azure Active Directory tenant ID"
  value       = var.tenant_id
  sensitive   = true
}

output "subscription_id" {
  description = "Azure subscription ID"
  value       = var.subscription_id
  sensitive   = true
}

# Git Integration Outputs
output "git_integration_environments" {
  description = "Environments with Git integration enabled"
  value       = [for k, v in var.environments : k if v.enable_git_integration]
}

output "git_provider" {
  description = "Configured Git provider for Fabric workspace"
  value       = var.git_provider
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

# Next Steps Information
output "next_steps" {
  description = "Next steps after deployment"
  value = var.enable_dev_git_integration ? {
    workspace_access_dev  = "Dev Workspace: Visit ${fabric_workspace.main["dev"].display_name} at https://app.fabric.microsoft.com/home?workspaceObjectId=${fabric_workspace.main["dev"].id}"
    workspace_access_test = "Test Workspace: Visit ${fabric_workspace.main["test"].display_name} at https://app.fabric.microsoft.com/home?workspaceObjectId=${fabric_workspace.main["test"].id}"
    workspace_access_prod = "Prod Workspace: Visit ${fabric_workspace.main["prod"].display_name} at https://app.fabric.microsoft.com/home?workspaceObjectId=${fabric_workspace.main["prod"].id}"
    git_status            = "✅ Git sync enabled for dev workspace"
    deployment_workflow   = "Push to dev branch = Auto-sync | PR to test branch = Pipeline deploy (1 reviewer) | PR to main branch = Pipeline deploy (2 reviewers)"
    repository_url        = "Repository: https://dev.azure.com/${var.azuredevops_org_name}/${azuredevops_project.main.name}/_git/${azuredevops_git_repository.main.name}"
    documentation         = "See README.md for complete deployment workflows"
  } : {
    workspace_access_dev  = "Dev Workspace: Visit ${fabric_workspace.main["dev"].display_name} at https://app.fabric.microsoft.com/home?workspaceObjectId=${fabric_workspace.main["dev"].id}"
    workspace_access_test = "Test Workspace: Visit ${fabric_workspace.main["test"].display_name} at https://app.fabric.microsoft.com/home?workspaceObjectId=${fabric_workspace.main["test"].id}"
    workspace_access_prod = "Prod Workspace: Visit ${fabric_workspace.main["prod"].display_name} at https://app.fabric.microsoft.com/home?workspaceObjectId=${fabric_workspace.main["prod"].id}"
    next_action           = "⚠️  Run .\\scripts\\init-repo-remote.ps1 to initialize repository with fabric-content folder on all branches"
    after_init            = "Then set enable_dev_git_integration = true in terraform.tfvars and run terraform apply again"
    why_needed            = "This ensures fabric-content folder exists before enabling Git sync to avoid GitProviderResourceNotFound errors"
  }
}