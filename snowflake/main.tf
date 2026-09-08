terraform {
  required_version = ">= 1.5"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = ">= 2.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }

    # Costory registration (optional). There is no costory_billing_datasource_snowflake
    # resource yet. Connect the service user in the Costory UI after apply.
    # costory = {
    #   source  = "costory-io/costory"
    #   version = "~> 0.2"
    # }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "organization_name" {
  type        = string
  description = "Snowflake organization name (provider organization_name). Can also be SNOWFLAKE_ORGANIZATION_NAME."
}

variable "account_name" {
  type        = string
  description = "Snowflake account name (provider account_name), not the locator. Can also be SNOWFLAKE_ACCOUNT_NAME."
}

variable "admin_user" {
  type        = string
  description = "Admin user Terraform authenticates as (ACCOUNTADMIN on an ORGADMIN-enabled account). Can also be SNOWFLAKE_USER."
}

variable "admin_private_key" {
  type        = string
  description = "PKCS#8 PEM private key for the Terraform admin user. Can also be SNOWFLAKE_PRIVATE_KEY."
  sensitive   = true
}

variable "admin_role" {
  type        = string
  description = "Role for Terraform. ACCOUNTADMIN (ORGADMIN-enabled account) or GLOBALORGADMIN."
  default     = "ACCOUNTADMIN"
}

variable "warehouse" {
  type        = string
  description = "Existing warehouse the billing-export user may run queries on."
}

variable "role_name" {
  type        = string
  description = "Account role granted the SNOWFLAKE billing / usage viewer database roles."
  default     = "BILLING_EXPORT"
}

variable "user_name" {
  type        = string
  description = "Service user that FinOps tools authenticate as."
  default     = "BILLING_EXPORT"
}

# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------
# Run this from an ORGADMIN-enabled account. Organization Usage grants fail
# from a regular account that cannot see SNOWFLAKE.ORGANIZATION_USAGE.

provider "snowflake" {
  organization_name = var.organization_name
  account_name      = var.account_name
  user              = var.admin_user
  role              = var.admin_role
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = var.admin_private_key
}

locals {
  account_identifier = "${var.organization_name}-${var.account_name}"
  rsa_public_key = replace(
    replace(
      replace(tls_private_key.billing_export.public_key_pem, "-----BEGIN PUBLIC KEY-----", ""),
      "-----END PUBLIC KEY-----",
      ""
    ),
    "\n",
    ""
  )
}

# -----------------------------------------------------------------------------
# Step 1 — Key pair for the service user
# -----------------------------------------------------------------------------

resource "tls_private_key" "billing_export" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# -----------------------------------------------------------------------------
# Step 2 — Role
# -----------------------------------------------------------------------------

resource "snowflake_account_role" "billing_export" {
  name    = var.role_name
  comment = "Read-only Snowflake billing export (ORGANIZATION_USAGE + ACCOUNT_USAGE query views)."
}

# -----------------------------------------------------------------------------
# Step 3 — SNOWFLAKE database roles
# -----------------------------------------------------------------------------
# ORGANIZATION_BILLING_VIEWER  = USAGE_IN_CURRENCY_DAILY (invoice $)
# ORGANIZATION_USAGE_VIEWER    = WAREHOUSE_METERING_HISTORY
# USAGE_VIEWER / GOVERNANCE_VIEWER = ACCOUNT_USAGE query attribution + history
# (this account only — not org-wide)

resource "snowflake_grant_database_role" "org_billing" {
  database_role_name = "\"SNOWFLAKE\".\"ORGANIZATION_BILLING_VIEWER\""
  parent_role_name   = snowflake_account_role.billing_export.name
}

resource "snowflake_grant_database_role" "org_usage" {
  database_role_name = "\"SNOWFLAKE\".\"ORGANIZATION_USAGE_VIEWER\""
  parent_role_name   = snowflake_account_role.billing_export.name
}

resource "snowflake_grant_database_role" "usage_viewer" {
  database_role_name = "\"SNOWFLAKE\".\"USAGE_VIEWER\""
  parent_role_name   = snowflake_account_role.billing_export.name
}

resource "snowflake_grant_database_role" "governance_viewer" {
  database_role_name = "\"SNOWFLAKE\".\"GOVERNANCE_VIEWER\""
  parent_role_name   = snowflake_account_role.billing_export.name
}

# -----------------------------------------------------------------------------
# Step 4 — Warehouse USAGE
# -----------------------------------------------------------------------------

resource "snowflake_grant_privileges_to_account_role" "warehouse" {
  account_role_name = snowflake_account_role.billing_export.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.warehouse
  }
}

# -----------------------------------------------------------------------------
# Step 5 — Service user
# -----------------------------------------------------------------------------

resource "snowflake_service_user" "billing_export" {
  name              = var.user_name
  login_name        = var.user_name
  display_name      = var.user_name
  comment           = "Key-pair user for Snowflake billing exports."
  default_role      = snowflake_account_role.billing_export.name
  default_warehouse = var.warehouse
  rsa_public_key    = local.rsa_public_key
}

resource "snowflake_grant_account_role" "billing_export_user" {
  role_name = snowflake_account_role.billing_export.name
  user_name = snowflake_service_user.billing_export.name
}

# -----------------------------------------------------------------------------
# Costory — register the Snowflake billing datasource
# Not supported as a Terraform resource yet. Paste host / user / role /
# warehouse / account identifier + privateKeyPem in Integrations → Snowflake.
# -----------------------------------------------------------------------------

# resource "costory_billing_datasource_snowflake" "main" {
#   name               = "Snowflake"
#   username           = snowflake_service_user.billing_export.name
#   role               = snowflake_account_role.billing_export.name
#   warehouse          = var.warehouse
#   host               = "${local.account_identifier}.snowflakecomputing.com"
#   account_identifier = local.account_identifier
#   private_key_pem    = tls_private_key.billing_export.private_key_pem_pkcs8
# }

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "user_name" {
  value = snowflake_service_user.billing_export.name
}

output "role_name" {
  value = snowflake_account_role.billing_export.name
}

output "warehouse" {
  value = var.warehouse
}

output "account_identifier" {
  description = "organization-account identifier for JDBC / FinOps tools."
  value       = local.account_identifier
}

output "host" {
  value = "${local.account_identifier}.snowflakecomputing.com"
}

output "private_key_pem" {
  description = "PKCS#8 private key for the billing-export service user (key-pair JWT)."
  value       = tls_private_key.billing_export.private_key_pem_pkcs8
  sensitive   = true
}
