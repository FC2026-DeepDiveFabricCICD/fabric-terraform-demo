# Azure DevOps Configuration
# This file defines Azure DevOps project, repository, and pipeline resources

# Azure DevOps Project
resource "azuredevops_project" "main" {
  name               = var.azuredevops_project_name
  description        = var.azuredevops_project_description
  visibility         = "private"
  version_control    = "Git"
  work_item_template = "Agile"

  features = {
    "boards"       = "enabled"
    "repositories" = "enabled"  
    "pipelines"    = "enabled"
    "testplans"    = "disabled"
    "artifacts"    = "enabled"
  }
}

# Add Service Principal to Azure DevOps with Stakeholder license
# Import existing: terraform import azuredevops_service_principal_entitlement.fabric_sp <sp-object-id>
resource "azuredevops_service_principal_entitlement" "fabric_sp" {
  origin_id            = azuread_service_principal.fabric_sp.object_id
  origin               = "aad"
  account_license_type = "express"
}

# Get the Project Administrators group
data "azuredevops_group" "project_administrators" {
  project_id = azuredevops_project.main.id
  name       = "Project Administrators"
}

# Add Service Principal to Project Administrators group
resource "azuredevops_group_membership" "fabric_sp_project_admin" {
  group = data.azuredevops_group.project_administrators.descriptor
  members = [
    azuredevops_service_principal_entitlement.fabric_sp.descriptor
  ]

  depends_on = [
    azuredevops_service_principal_entitlement.fabric_sp
  ]
}

# Azure DevOps Git Repository
# NOTE: Repository is created empty ("Clean" init). After first terraform apply,
# run scripts/init-repo-remote.ps1 to create branches and set main as default.
# See README.md for complete deployment steps.
resource "azuredevops_git_repository" "main" {
  project_id = azuredevops_project.main.id
  name       = var.azuredevops_repository_name
  
  initialization {
    init_type = "Clean"
  }

  lifecycle {
    ignore_changes = [
      # Ignore changes to initialization after first creation
      initialization,
    ]
  }
}

# Repository Branch Policies
# Dev branch: No PR required (direct commits allowed for Git sync)
# Test branch: 1 reviewer required
# Main branch: 2 reviewers required

# Branch Policy for Test Branch - Minimum Reviewers
# Only created after repository is initialized (enable_dev_git_integration = true)
# Allows pusher to approve their own PR, no build validation required
resource "azuredevops_branch_policy_min_reviewers" "test_branch_policy" {
  count = var.enable_dev_git_integration ? 1 : 0
  
  project_id = azuredevops_project.main.id

  enabled  = true
  blocking = true

  settings {
    reviewer_count                         = 1
    submitter_can_vote                     = true
    last_pusher_cannot_approve            = false
    allow_completion_with_rejects_or_waits = false
    on_push_reset_approved_votes          = true

    scope {
      repository_id  = azuredevops_git_repository.main.id
      repository_ref = "refs/heads/test"
      match_type     = "Exact"
    }
  }

  depends_on = [azuredevops_git_repository.main]
}

# Branch Policy for Main Branch - Minimum Reviewers
# Only created after repository is initialized (enable_dev_git_integration = true)
resource "azuredevops_branch_policy_min_reviewers" "main_branch_policy" {
  count = var.enable_dev_git_integration ? 1 : 0
  
  project_id = azuredevops_project.main.id

  enabled  = true
  blocking = true

  settings {
    reviewer_count                         = 2
    submitter_can_vote                     = false
    last_pusher_cannot_approve            = true
    allow_completion_with_rejects_or_waits = false
    on_push_reset_approved_votes          = true

    scope {
      repository_id  = azuredevops_git_repository.main.id
      repository_ref = "refs/heads/main"
      match_type     = "Exact"
    }
  }

  depends_on = [azuredevops_git_repository.main]
}

# Repository Policy - Build Validation (requires successful build before PR completion)
# Applies to main branch only (not test or dev)
# Test branch: No build validation required (pusher can self-approve)
# Only created after repository is initialized (enable_dev_git_integration = true)
resource "azuredevops_branch_policy_build_validation" "test_branch_build_policy" {
  count = 0  # Disabled - no build validation required for test branch
  
  project_id = azuredevops_project.main.id

  enabled  = true
  blocking = true

  settings {
    display_name        = "Fabric Content Validation - Test"
    build_definition_id = azuredevops_build_definition.fabric_deploy[0].id
    valid_duration     = 720  # 12 hours
    filename_patterns = [
      "/fabric-content/*",
      "/pipelines/*"
    ]

    scope {
      repository_id  = azuredevops_git_repository.main.id
      repository_ref = "refs/heads/test"
      match_type     = "Exact"
    }
  }

  depends_on = [
    azuredevops_git_repository.main,
    azuredevops_build_definition.fabric_deploy
  ]
}

resource "azuredevops_branch_policy_build_validation" "main_branch_build_policy" {
  count = (var.create_deployment_pipeline && var.enable_dev_git_integration) ? 1 : 0
  
  project_id = azuredevops_project.main.id

  enabled  = true
  blocking = true

  settings {
    display_name        = "Fabric Content Validation - Main"
    build_definition_id = azuredevops_build_definition.fabric_deploy[0].id
    valid_duration     = 720  # 12 hours
    filename_patterns = [
      "/fabric-content/*",
      "/pipelines/*"
    ]

    scope {
      repository_id  = azuredevops_git_repository.main.id
      repository_ref = "refs/heads/main"
      match_type     = "Exact"
    }
  }

  depends_on = [
    azuredevops_git_repository.main,
    azuredevops_build_definition.fabric_deploy
  ]
}

# Service Connection to Azure (for accessing Fabric and Azure resources)
resource "azuredevops_serviceendpoint_azurerm" "fabric" {
  count = var.create_deployment_pipeline ? 1 : 0
  
  project_id                             = azuredevops_project.main.id
  service_endpoint_name                  = "Azure-${var.project_name}"
  description                           = "Service connection for Fabric multi-workspace deployment"
  service_endpoint_authentication_scheme = "ServicePrincipal"
  
  # OIDC Configuration for secure authentication
  azurerm_spn_tenantid      = var.tenant_id
  azurerm_subscription_id   = var.subscription_id
  azurerm_subscription_name = "Fabric Deployment Subscription"
  
  # Service Principal configuration
  credentials {
    serviceprincipalid  = azuread_application.fabric_sp.client_id
    serviceprincipalkey = azuread_application_password.fabric_sp_secret.value
  }

  depends_on = [
    azuread_application_password.fabric_sp_secret
  ]
}

# Variable Groups for Pipeline Configuration (one per environment)
# Each variable group contains workspace-specific configuration with environment-specific variable names
# This prevents variable name conflicts when multiple groups are loaded in the pipeline
resource "azuredevops_variable_group" "fabric_deployment" {
  for_each = var.create_deployment_pipeline ? var.environments : {}
  
  project_id   = azuredevops_project.main.id
  name         = "Fabric-Deployment-${each.key}"
  description  = "Variables for Fabric ${each.value.description_suffix} workspace deployment"
  allow_access = true

  variable {
    name  = "FABRIC_WORKSPACE_ID_${upper(each.key)}"
    value = fabric_workspace.main[each.key].id
  }

  variable {
    name         = "FABRIC_CAPACITY_ID_${upper(each.key)}"
    secret_value = var.fabric_capacity_id
    is_secret    = true
  }

  variable {
    name  = "AZURE_SUBSCRIPTION_ID_${upper(each.key)}" 
    value = var.subscription_id
  }

  variable {
    name  = "AZURE_TENANT_ID_${upper(each.key)}"
    value = var.tenant_id
  }

  variable {
    name  = "ENVIRONMENT_${upper(each.key)}"
    value = each.key
  }

  variable {
    name  = "PROJECT_NAME_${upper(each.key)}"
    value = var.project_name
  }

  variable {
    name  = "SERVICE_PRINCIPAL_ID_${upper(each.key)}"
    value = azuread_application.fabric_sp.client_id
  }

  variable {
    name         = "SERVICE_PRINCIPAL_SECRET_${upper(each.key)}"
    secret_value = azuread_application_password.fabric_sp_secret.value
    is_secret    = true
  }

  # Connection ID for Git credentials (only for dev environment with Git integration enabled)
  dynamic "variable" {
    for_each = (var.enable_dev_git_integration && each.value.enable_git_integration) ? [1] : []
    content {
      name  = "FABRIC_GIT_CONNECTION_ID_${upper(each.key)}"
      value = fabric_connection.azdo_git[each.key].id
    }
  }

  depends_on = [
    fabric_workspace.main,
    azuread_service_principal.fabric_sp
  ]
}

# Build Definition (Pipeline) for Fabric Content Deployment
# Triggers on dev, test, and main branches
# Pipeline automatically selects the correct variable group based on branch
resource "azuredevops_build_definition" "fabric_deploy" {
  count = var.create_deployment_pipeline ? 1 : 0
  
  project_id = azuredevops_project.main.id
  name       = "Fabric-Content-Deploy"
  path       = "\\Fabric"

  ci_trigger {
    use_yaml = true
  }

  repository {
    repo_type   = "TfsGit"
    repo_id     = azuredevops_git_repository.main.id
    branch_name = "refs/heads/dev"
    yml_path    = "pipelines/fabric-deploy.yaml"
  }

  depends_on = [
    azuredevops_git_repository.main,
    azuredevops_variable_group.fabric_deployment
  ]
}

# Security: Authorize service endpoint for all pipelines in project
resource "azuredevops_pipeline_authorization" "fabric_service_connection" {
  count = var.create_deployment_pipeline ? 1 : 0
  
  project_id  = azuredevops_project.main.id
  resource_id = azuredevops_serviceendpoint_azurerm.fabric[0].id
  type        = "endpoint"

  depends_on = [
    azuredevops_serviceendpoint_azurerm.fabric,
    azuredevops_build_definition.fabric_deploy
  ]
}

# Security: Authorize variable groups for pipeline usage
resource "azuredevops_pipeline_authorization" "fabric_variable_groups" {
  for_each = var.create_deployment_pipeline ? var.environments : {}
  
  project_id  = azuredevops_project.main.id
  resource_id = azuredevops_variable_group.fabric_deployment[each.key].id
  type        = "variablegroup"

  depends_on = [
    azuredevops_variable_group.fabric_deployment,
    azuredevops_build_definition.fabric_deploy
  ]
}