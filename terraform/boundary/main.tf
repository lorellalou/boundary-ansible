
resource "boundary_scope" "global" {
  global_scope = true
  scope_id     = "global"
}

resource "boundary_auth_method_password" "admin_password" {
    scope_id                 = boundary_scope.global.id
}

resource "boundary_user" "admin" {
  name        = "admin"
  description = "User resource for admin"
  scope_id    = boundary_scope.global.id
  account_ids = [boundary_account_password.admin.id]
}

resource "boundary_account_password" "admin" {
  auth_method_id = boundary_auth_method_password.admin_password.id
  login_name     = "admin"
  password       = var.admin_password
}

resource "boundary_role" "global_admin" {
  name        = "admin"
  description = "Administrator role"
  principal_ids = concat(
    [boundary_user.admin.id]
  )
  grant_strings   = ["id=*;type=*;actions=*"]
  scope_id = boundary_scope.global.id
}

resource "boundary_scope" "corp" {
  name                     = "Corp"
  scope_id                 = boundary_scope.global.id
  auto_create_admin_role   = true
  auto_create_default_role = true
}

resource "boundary_auth_method_password" "corp_password" {
    scope_id                 = boundary_scope.corp.id
}

resource "boundary_auth_method_oidc" "corp_oidc" {
    scope_id                 = boundary_scope.corp.id
    issuer                   = var.oidc_issuer
    client_id                = var.oidc_client
    client_secret            = var.oidc_secret
    api_url_prefix           = var.api_url_prefix
    signing_algorithms       = ["RS256"]
    claims_scopes            = ["profile", "boundary_roles", "boundary_context"]  
}

resource "boundary_managed_group" "admin_internal" {
  auth_method_id             = boundary_auth_method_oidc.corp_oidc.id
  filter                     = "\"CorpAdmin\" in \"/token/boundary_roles\" and \"/token/boundary_context\" == \"Internal\" and \"/token/name\" == \"lorellalou\""
}

resource "boundary_account_oidc" "lorellalou" {
  name           = "lorellalou"
  description    = "Laurent ROLAZ"
  auth_method_id = boundary_auth_method_oidc.corp_oidc.id
  issuer         = "https://dev-xz118zjh1qebvv1i.eu.auth0.com/"
  subject        = "auth0|64b94cd70b7eb7c57971eb08"
}

resource "boundary_user" "lorellalou" {
  name        = "lorellalou"
  description = "Laurent ROLAZ"
  scope_id    = boundary_scope.corp.id
  account_ids = [boundary_account_oidc.lorellalou.id]
}

// add org-level role for administration access
resource "boundary_role" "organization_admin" {
  name        = "admin"
  description = "Administrator role"
  principal_ids = concat(
    [boundary_user.admin.id]
  )
  grant_strings   = [
    "id=*;type=*;actions=*"
    ]
  scope_id = boundary_scope.corp.id
}

resource "boundary_role" "core_infra_admin" {
  name        = "admin"
  description = "Administrator role"
  principal_ids = concat(
    [boundary_user.admin.id],
    [boundary_managed_group.admin_internal.id]
  )
  grant_strings   = [
    "id=${boundary_target.backend_servers_rdp.id};type=target;actions=authorize-session",
    "id=${boundary_target.rke_appliance.id};type=target;actions=authorize-session",
    "id=${boundary_target.boundary_appliance.id};type=target;actions=authorize-session",
    "id=*;type=*;actions=*"
    ]
  scope_id = boundary_scope.core_infra.id
}

// create a project for core infrastructure
resource "boundary_scope" "core_infra" {
  description              = "Core infrastrcture"
  scope_id                 = boundary_scope.corp.id
  auto_create_admin_role   = true
}

resource "boundary_host_catalog_static" "core_catalog" {
  name        = "core_catalog"
  description = "core servers host catalog"
  scope_id    = boundary_scope.core_infra.id
}

resource "boundary_host_static" "windows_servers" {
  for_each        = var.backend_server_windows
  type            = "static"
  name            = "${each.value}"
  description     = "Windows server host"
  address         = "${each.key}"
  host_catalog_id = boundary_host_catalog_static.core_catalog.id
}

resource "boundary_host_set_static" "windows_servers_rdp" {
  type            = "static"
  name            = "windows_servers_rdp"
  description     = "Host set for Windows servers"
  host_catalog_id = boundary_host_catalog_static.core_catalog.id
  host_ids        = [for host in boundary_host_static.windows_servers : host.id]
}

// create target for accessing backend servers on port :3389
resource "boundary_target" "backend_servers_rdp" {
  type         = "tcp"
  name         = "windows_servers_rdp"
  description  = "Backend RDP target"
  scope_id     = boundary_scope.core_infra.id
  default_port = "3389"

  host_source_ids = [
    boundary_host_set_static.windows_servers_rdp.id
  ]
}

resource "boundary_host_static" "boundary_appliance" {
  for_each        = var.backend_server_boundary
  type            = "static"
  name            = "${each.value}"
  description     = "Boundary server host"
  address         = "${each.key}"
  host_catalog_id = boundary_host_catalog_static.core_catalog.id
}

resource "boundary_host_set_static" "boundary_appliance" {
  type            = "static"
  name            = "boundary_appliance"
  description     = "Host set for Windows servers"
  host_catalog_id = boundary_host_catalog_static.core_catalog.id
  host_ids        = [for host in boundary_host_static.boundary_appliance : host.id]
}

// create target for accessing backend servers on port :3389
resource "boundary_target" "boundary_appliance" {
  type         = "tcp"
  name         = "boundary_appliance"
  description  = "Backend SSH target"
  scope_id     = boundary_scope.core_infra.id
  default_port = "22"

  host_source_ids = [
    boundary_host_set_static.boundary_appliance.id
  ]
}


resource "boundary_host_static" "rke_appliance" {
  for_each        = var.backend_server_rke
  type            = "static"
  name            = "${each.value}"
  description     = "RKE server host"
  address         = "${each.key}"
  host_catalog_id = boundary_host_catalog_static.core_catalog.id
}

resource "boundary_host_set_static" "rke_appliance" {
  type            = "static"
  name            = "rke_appliance"
  description     = "Host set for RKE servers"
  host_catalog_id = boundary_host_catalog_static.core_catalog.id
  host_ids        = [for host in boundary_host_static.rke_appliance : host.id]
}

// create target for accessing backend servers on port :3389
resource "boundary_target" "rke_appliance" {
  type         = "tcp"
  name         = "rke_appliance"
  description  = "Backend SSH target"
  scope_id     = boundary_scope.core_infra.id
  default_port = "22"

  host_source_ids = [
    boundary_host_set_static.rke_appliance.id
  ]
}

