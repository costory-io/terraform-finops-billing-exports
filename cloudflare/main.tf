terraform {
  required_version = ">= 1.5"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.0"
    }

    # Costory registration (optional). There is no costory_billing_datasource_cloudflare
    # resource yet. Connect the token in the Costory UI after apply.
    # costory = {
    #   source  = "costory-io/costory"
    #   version = "~> 0.2"
    # }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "cloudflare_api_token" {
  type        = string
  description = "Existing API token used by Terraform to mint the billing-export token (needs API Tokens Write). Can also be CLOUDFLARE_API_TOKEN."
  sensitive   = true
}

variable "account_id" {
  type        = string
  description = "Cloudflare account ID the billing-export token is scoped to."
}

variable "token_name" {
  type        = string
  description = "Display name for the billing-export API token."
  default     = "billing-export"
}

# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# -----------------------------------------------------------------------------
# Step 1 — Billing Read permission group
# -----------------------------------------------------------------------------
# Account → Billing → Read. Do not grant Billing Write.

data "cloudflare_api_token_permission_groups_list" "billing_read" {
  name  = "Billing%20Read"
  scope = "com.cloudflare.api.account"
}

locals {
  billing_read_permission_id = data.cloudflare_api_token_permission_groups_list.billing_read.result[0].id
}

# -----------------------------------------------------------------------------
# Step 2 — Least-privilege API token
# -----------------------------------------------------------------------------

resource "cloudflare_api_token" "billing_export" {
  name = var.token_name

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = local.billing_read_permission_id
    }]
    resources = jsonencode({
      "com.cloudflare.api.account.${var.account_id}" = "*"
    })
  }]
}

# -----------------------------------------------------------------------------
# Costory — register the Cloudflare billing datasource
# Not supported as a Terraform resource yet. Paste account_id + api_token in
# Integrations → Cloudflare.
# -----------------------------------------------------------------------------

# resource "costory_billing_datasource_cloudflare" "main" {
#   name       = "Cloudflare"
#   api_token  = cloudflare_api_token.billing_export.value
#   account_id = var.account_id
# }

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "account_id" {
  value = var.account_id
}

output "api_token_id" {
  value = cloudflare_api_token.billing_export.id
}

output "api_token" {
  description = "Bearer token for GET /accounts/{id}/billing-usage."
  value       = cloudflare_api_token.billing_export.value
  sensitive   = true
}
