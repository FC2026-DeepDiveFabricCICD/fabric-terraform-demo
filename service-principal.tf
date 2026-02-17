# Service Principal and Azure AD Group Configuration
# This file defines the service principal for Fabric access and manages Azure AD group membership

# Data source to get existing Azure AD group (if it exists)
data "azuread_group" "existing_group" {
  count        = var.create_azure_ad_group ? 0 : 1
  display_name = var.azure_ad_group_name
}

# Create Azure AD group if it doesn't exist and create_azure_ad_group is true
resource "azuread_group" "fabric_group" {
  count            = var.create_azure_ad_group ? 1 : 0
  display_name     = var.azure_ad_group_name
  description      = "Azure AD group for ${var.project_name} Fabric service principals (multi-workspace)"
  security_enabled = true
  
  # Prevent accidental deletion of the group 
  lifecycle {
    prevent_destroy = true
  }
}

# Local value to get the group object ID regardless of whether it was created or existing
locals {
  azure_ad_group_id = var.create_azure_ad_group ? azuread_group.fabric_group[0].object_id : data.azuread_group.existing_group[0].object_id
}

# Azure AD Application for Service Principal
resource "azuread_application" "fabric_sp" {
  display_name = var.service_principal_name
  description  = "Service principal for ${var.project_name} Fabric workspace access (all environments)"
  
  # Required resource access for Microsoft Fabric
  required_resource_access {
    resource_app_id = "00000009-0000-0000-c000-000000000000" # Power BI Service
    
    resource_access {
      id   = "4ae1bf56-f562-4747-b7bc-2fa0874ed46f" # Content.Create
      type = "Scope"
    }
    
    resource_access {
      id   = "2448370f-f988-42cd-909c-6528eced8047" # Dataset.ReadWrite.All
      type = "Role"
    }
    
    resource_access {
      id   = "7f33e027-4039-419b-938e-2f8ca153e68e" # Workspace.ReadWrite.All
      type = "Role"
    }
  }
  
  # Web configuration for modern authentication
  web {
    homepage_url  = "https://example.com"
    redirect_uris = []
  }
  
  tags = [
    "Project:${var.project_name}",
    "ManagedBy:Terraform",
    "Purpose:MultiWorkspaceAccess"
  ]
}

# Service Principal from the Application
resource "azuread_service_principal" "fabric_sp" {
  client_id                     = azuread_application.fabric_sp.client_id
  app_role_assignment_required  = false
  
  description = "Service principal for ${var.project_name} Fabric workspace access (all environments)"
  
  tags = [
    "Project:${var.project_name}",
    "ManagedBy:Terraform",
    "Purpose:MultiWorkspaceAccess"
  ]
}

# Add the Service Principal to the Azure AD Group
resource "azuread_group_member" "fabric_sp_member" {
  group_object_id   = local.azure_ad_group_id
  member_object_id  = azuread_service_principal.fabric_sp.object_id
}

# Generate a client secret for the service principal
resource "azuread_application_password" "fabric_sp_secret" {
  application_id = azuread_application.fabric_sp.id
  display_name   = "${var.service_principal_name}-secret"
  
  # Secret expires in 2 years
  end_date_relative = "17520h" # 2 years in hours
}

# Wait for Azure AD propagation before assigning Fabric roles
resource "time_sleep" "wait_for_sp_propagation" {
  depends_on = [azuread_service_principal.fabric_sp]
  
  create_duration = "60s"
}

# Grant the service principal admin access to all Fabric workspaces
# Creates one role assignment per workspace (dev, test, prod)
resource "fabric_workspace_role_assignment" "service_principal_admin" {
  for_each = var.environments
  
  workspace_id = fabric_workspace.main[each.key].id
  principal = {
    id   = azuread_service_principal.fabric_sp.object_id
    type = "ServicePrincipal"
  }
  role = "Admin"

  depends_on = [
    fabric_workspace.main,
    azuread_service_principal.fabric_sp,
    time_sleep.wait_for_sp_propagation
  ]
}