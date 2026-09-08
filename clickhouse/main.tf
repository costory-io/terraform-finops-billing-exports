terraform {
  required_version = ">= 1.5"

  required_providers {
    clickhouse = {
      source  = "ClickHouse/clickhouse"
      version = ">= 3.0"
    }

    # Costory registration (optional). There is no costory_billing_datasource_clickhouse
    # resource yet. Connect the key in the Costory UI after apply.
    # costory = {
    #   source  = "costory-io/costory"
    #   version = "~> 0.2"
    # }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "organization_id" {
  type        = string
  description = "ClickHouse Cloud organization ID. Can also be CLICKHOUSE_ORG_ID."
}

variable "admin_token_key" {
  type        = string
  description = "Existing admin API key ID used by Terraform. Can also be CLICKHOUSE_CLOUD_API_KEY."
  sensitive   = true
}

variable "admin_token_secret" {
  type        = string
  description = "Existing admin API key secret. Can also be CLICKHOUSE_CLOUD_API_SECRET."
  sensitive   = true
}

variable "billing_api_key_id" {
  type        = string
  description = "Optional ID of a ClickHouse Cloud API key to attach to the billing-export role. Leave empty if you will assign the role in the console."
  default     = ""
}

# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------
# The official provider can manage roles, but it cannot create organization API
# keys yet (https://github.com/ClickHouse/terraform-provider-clickhouse/issues/585).
# Create the key in the ClickHouse Cloud console (or POST /v1/organizations/{id}/keys)
# and assign it the role this stack creates.

provider "clickhouse" {
  organization_id = var.organization_id
  token_key       = var.admin_token_key
  token_secret    = var.admin_token_secret
}

# -----------------------------------------------------------------------------
# Step 1 — Built-in Billing role (reference)
# -----------------------------------------------------------------------------
# System role "Billing" can view usage and invoices. Prefer a custom role with
# only view-billing so the export key cannot change payment methods.

data "clickhouse_role" "billing" {
  name = "Billing"
}

# -----------------------------------------------------------------------------
# Step 2 — Least-privilege custom role
# -----------------------------------------------------------------------------
# control-plane:organization:view         = read org metadata
# control-plane:organization:view-billing = usage, invoices, cost lines
# Avoid manage-billing (payment methods).

resource "clickhouse_role" "billing_export" {
  name = "billing-export-reader"

  policies = [
    {
      effect = "ALLOW"
      permissions = [
        "control-plane:organization:view",
        "control-plane:organization:view-billing",
      ]
      resources = ["organization/${var.organization_id}"]
    },
  ]
}

# -----------------------------------------------------------------------------
# Step 3 — Attach an existing API key to the custom role
# -----------------------------------------------------------------------------
# Create the key in the console with this role, or pass its ID here.
# clickhouse_role_assignment owns the full actor list for this role, so only
# attach keys that should have billing-export access.

resource "clickhouse_role_assignment" "billing_export" {
  count = var.billing_api_key_id != "" ? 1 : 0

  role_id     = clickhouse_role.billing_export.id
  api_key_ids = [var.billing_api_key_id]
}

# -----------------------------------------------------------------------------
# Costory — register the ClickHouse billing datasource
# Not supported as a Terraform resource yet. Paste organization_id + key/secret
# in Integrations → ClickHouse.
# -----------------------------------------------------------------------------

# resource "costory_billing_datasource_clickhouse" "main" {
#   name            = "ClickHouse Cloud"
#   organization_id = var.organization_id
#   api_key         = var.billing_api_key
#   api_secret      = var.billing_api_secret
# }

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "organization_id" {
  value = var.organization_id
}

output "billing_export_role_id" {
  description = "Custom role to assign to the billing-export API key."
  value       = clickhouse_role.billing_export.id
}

output "system_billing_role_id" {
  description = "Built-in Billing system role (broader than the custom role)."
  value       = data.clickhouse_role.billing.id
}
