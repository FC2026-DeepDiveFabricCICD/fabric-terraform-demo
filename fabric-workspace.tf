# Microsoft Fabric Workspace Configuration
# This file defines the Fabric workspace resources and configuration
# Three workspaces are created: {prefix}-dev, {prefix}-test, {prefix}-prod
# Git integration is enabled only for the dev workspace

# Data sources to look up user Object IDs from UPNs (email addresses)
data "azuread_user" "admin_users" {
  for_each            = toset(var.fabric_workspace_admin_users)
  user_principal_name = each.value
}

data "azuread_user" "member_users" {
  for_each            = toset(var.fabric_workspace_member_users)
  user_principal_name = each.value
}

# Microsoft Fabric Workspaces (one for each environment: dev, test, prod)
resource "fabric_workspace" "main" {
  for_each = var.environments
  
  display_name = "${var.workspace_prefix}-${each.value.workspace_suffix}"
  description  = "${var.fabric_workspace_description} ${each.value.description_suffix}"
  capacity_id  = var.fabric_capacity_id

  # Workspace configuration
  # Each workspace is created with the same capacity but different configurations
  
  lifecycle {
    # Prevent accidental deletion of the workspace
    prevent_destroy = true
    
    # Ignore changes to capacity assignment during updates
    ignore_changes = [
      capacity_id
    ]
  }
}

# Fabric Workspace Role Assignments for Admin Users
# Note: The user who creates the workspace is automatically an Admin.
# Do not include that user in fabric_workspace_admin_users to avoid conflicts.
# Creates role assignments for all admin users in all workspaces
resource "fabric_workspace_role_assignment" "admin_users" {
  for_each = {
    for pair in flatten([
      for env_key, env in var.environments : [
        for user_key, user in data.azuread_user.admin_users : {
          key          = "${env_key}-${user_key}"
          workspace_id = fabric_workspace.main[env_key].id
          user_id      = user.object_id
        }
      ]
    ]) : pair.key => pair
  }
  
  workspace_id = each.value.workspace_id
  principal = {
    id   = each.value.user_id
    type = "User"
  }
  role = "Admin"

  lifecycle {
    ignore_changes = [role]
  }

  depends_on = [fabric_workspace.main]
}

# Fabric Workspace Role Assignments for Member Users
# Creates role assignments for all member users in all workspaces
resource "fabric_workspace_role_assignment" "member_users" {
  for_each = {
    for pair in flatten([
      for env_key, env in var.environments : [
        for user_key, user in data.azuread_user.member_users : {
          key          = "${env_key}-${user_key}"
          workspace_id = fabric_workspace.main[env_key].id
          user_id      = user.object_id
        }
      ]
    ]) : pair.key => pair
  }
  
  workspace_id = each.value.workspace_id
  principal = {
    id   = each.value.user_id
    type = "User"
  }
  role = "Member"

  depends_on = [fabric_workspace.main]
}

# Git Repository Configuration (for dev environment only)
# Only the dev workspace has Git integration enabled for direct synchronization
# Test and prod workspaces are deployed via the Azure DevOps pipeline
# The service principal running Terraform must have access to the Azure DevOps repo.
# The SP is granted access via azuredevops_serviceendpoint_azurerm in azure-devops.tf.

# Create a Fabric Connection with Service Principal credentials for Git integration
# This is required because fabric_workspace_git only supports SP auth with ConfiguredConnection
# Only created when enable_dev_git_integration = true AND environment has enable_git_integration = true
resource "fabric_connection" "azdo_git" {
  for_each = var.enable_dev_git_integration ? { for k, v in var.environments : k => v if v.enable_git_integration } : {}

  display_name      = "${var.project_name}-${each.key}-azdo-git"
  connectivity_type = "ShareableCloud"
  privacy_level     = "Organizational"

  connection_details = {
    type            = "AzureDevOpsSourceControl"
    creation_method = "AzureDevOpsSourceControl.Contents"
    parameters = [
      {
        name  = "url"
        value = "https://dev.azure.com/${var.azuredevops_org_name}/${azuredevops_project.main.name}/_git/${azuredevops_git_repository.main.name}/"
      }
    ]
  }

  credential_details = {
    connection_encryption = "NotEncrypted"
    credential_type       = "ServicePrincipal"
    single_sign_on_type   = "None"
    skip_test_connection  = false
    service_principal_credentials = {
      client_id               = azuread_application.fabric_sp.client_id
      client_secret_wo        = azuread_application_password.fabric_sp_secret.value
      client_secret_wo_version = 1
      tenant_id               = var.tenant_id
    }
  }

  depends_on = [
    azuread_application_password.fabric_sp_secret,
    azuredevops_project.main,
    azuredevops_git_repository.main
  ]
}

# Git Workspace Integration (dev workspace only)
# Links the dev workspace to the dev branch in Azure DevOps
# Only created when enable_dev_git_integration = true
resource "fabric_workspace_git" "main" {
  for_each = var.enable_dev_git_integration ? { for k, v in var.environments : k => v if v.enable_git_integration } : {}
  
  workspace_id = fabric_workspace.main[each.key].id
  
  initialization_strategy = "PreferWorkspace"
  
  # Git configuration to connect to the Azure DevOps repository
  git_provider_details = {
    git_provider_type = var.git_provider
    organization_name = var.azuredevops_org_name
    project_name      = azuredevops_project.main.name
    repository_name   = azuredevops_git_repository.main.name
    branch_name       = each.value.git_branch_name
    directory_name    = "/fabric-content"
  }

  # ConfiguredConnection - required for Service Principal authentication
  git_credentials = {
    source        = "ConfiguredConnection"
    connection_id = fabric_connection.azdo_git[each.key].id
  }

  depends_on = [
    fabric_workspace.main,
    azuredevops_git_repository.main,
    fabric_connection.azdo_git
  ]
}

# Optional: Fabric Workspace Settings (when available in provider)
# These settings configure workspace behavior and security
# Note: In multi-workspace setup, settings may vary by environment
locals {
  workspace_settings = {
    # Security settings
    external_sharing_enabled     = false
    guest_access_enabled        = false
    tenant_setting_override     = true
    
    # Development settings (configured per workspace in environments map)
    # developer_mode_enabled varies by environment
    # auto_install_power_bi_apps varies by environment
    
    # Git integration settings (enabled for dev only)
    # git_integration_enabled configured via environments map
    # git_sync_enabled configured via environments map
    
    # Monitoring and logging
    audit_log_enabled          = var.enable_monitoring
    usage_metrics_enabled      = var.enable_monitoring
  }
}

# Workspace settings are now managed purely through Terraform outputs
# Service principal credentials are stored as sensitive outputs for external use