terraform {
  required_version = ">= 1.5"

  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = ">= 4.0"
    }

    # Costory registration (optional). There is no costory_billing_datasource_aiven
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

variable "aiven_api_token" {
  type        = string
  description = "Aiven token used by Terraform (organization admin). Can also be AIVEN_TOKEN."
  sensitive   = true
}

variable "organization_id" {
  type        = string
  description = "Aiven organization ID (org1…)."
}

variable "application_user_name" {
  type        = string
  description = "Name of the dedicated application user for billing exports."
  default     = "billing-export"
}

# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------

provider "aiven" {
  api_token = var.aiven_api_token
}

# -----------------------------------------------------------------------------
# Step 1 — Dedicated application user
# -----------------------------------------------------------------------------
# Application users are non-human principals. Create one per integration so you
# can rotate or revoke billing access without touching other automation.

resource "aiven_organization_application_user" "billing_export" {
  organization_id = var.organization_id
  name            = var.application_user_name
}

# -----------------------------------------------------------------------------
# Step 2 — organization:billing:read
# -----------------------------------------------------------------------------
# aiven_organization_permission owns EVERY principal on this
# organization/resource pair. Merge this permissions {} block into the
# resource that already manages your org, or import first:
#   terraform import aiven_organization_permission.billing_export \
#     ORGANIZATION_ID/organization/ORGANIZATION_ID
# then add the billing-export principal alongside the existing ones.

# resource "aiven_organization_permission" "billing_export" {
#   organization_id = var.organization_id
#   resource_type   = "organization"
#   resource_id     = var.organization_id
#
#   permissions {
#     principal_id   = aiven_organization_application_user.billing_export.user_id
#     principal_type = "user"
#     permissions    = ["organization:billing:read"]
#   }
# }

# -----------------------------------------------------------------------------
# Step 3 — API token for the application user
# -----------------------------------------------------------------------------

resource "aiven_organization_application_user_token" "billing_export" {
  organization_id = var.organization_id
  user_id         = aiven_organization_application_user.billing_export.user_id
  description     = "Read-only token for Aiven billing exports"
}

# -----------------------------------------------------------------------------
# Costory — register the Aiven billing datasource
# Not supported as a Terraform resource yet. Paste organization_id + token in
# Integrations → Aiven.
# -----------------------------------------------------------------------------

# resource "costory_billing_datasource_aiven" "main" {
#   name            = "Aiven"
#   organization_id = var.organization_id
#   api_token       = aiven_organization_application_user_token.billing_export.full_token
# }

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "organization_id" {
  value = var.organization_id
}

output "application_user_id" {
  value = aiven_organization_application_user.billing_export.user_id
}

output "api_token" {
  description = "Application-user token for the Aiven Billing API."
  value       = aiven_organization_application_user_token.billing_export.full_token
  sensitive   = true
}
