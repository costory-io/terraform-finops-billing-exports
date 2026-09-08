terraform {
  required_version = ">= 1.5"

  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = ">= 2.0"
    }

    # Costory registration (optional). There is no costory_billing_datasource_confluent
    # resource yet. Connect the Cloud API key in the Costory UI after apply.
    # costory = {
    #   source  = "costory-io/costory"
    #   version = "~> 0.2"
    # }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "confluent_cloud_api_key" {
  type        = string
  description = "Cloud API key of an OrganizationAdmin (or equivalent) used by Terraform. Can also be CONFLUENT_CLOUD_API_KEY."
  sensitive   = true
}

variable "confluent_cloud_api_secret" {
  type        = string
  description = "Cloud API secret for the Terraform principal. Can also be CONFLUENT_CLOUD_API_SECRET."
  sensitive   = true
}

variable "service_account_name" {
  type        = string
  description = "Display name for the billing-export service account."
  default     = "billing-export"
}

# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

# -----------------------------------------------------------------------------
# Step 1 — Organization scope
# -----------------------------------------------------------------------------

data "confluent_organization" "current" {}

# -----------------------------------------------------------------------------
# Step 2 — Service account
# -----------------------------------------------------------------------------

resource "confluent_service_account" "billing_export" {
  display_name = var.service_account_name
  description  = "Read Confluent Cloud costs via the billing/v1/costs API."
}

# -----------------------------------------------------------------------------
# Step 3 — BillingAdmin at organization scope
# -----------------------------------------------------------------------------
# BillingAdmin is the least-privilege predefined role that can call
# GET /billing/v1/costs. There is no read-only billing role.
# Do not add a trailing slash on the organization CRN.

resource "confluent_role_binding" "billing_export" {
  principal   = "User:${confluent_service_account.billing_export.id}"
  role_name   = "BillingAdmin"
  crn_pattern = data.confluent_organization.current.resource_name
}

# -----------------------------------------------------------------------------
# Step 4 — Cloud API key owned by the service account
# -----------------------------------------------------------------------------
# Omit managed_resource so this is a Cloud API key (not a Kafka cluster key).

resource "confluent_api_key" "billing_export" {
  display_name = "billing-export"
  description  = "Cloud API key for Confluent billing exports"

  owner {
    id          = confluent_service_account.billing_export.id
    api_version = confluent_service_account.billing_export.api_version
    kind        = confluent_service_account.billing_export.kind
  }

  depends_on = [confluent_role_binding.billing_export]

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Costory — register the Confluent billing datasource
# Not supported as a Terraform resource yet. Paste the API key + secret in
# Integrations → Confluent.
# -----------------------------------------------------------------------------

# resource "costory_billing_datasource_confluent" "main" {
#   name       = "Confluent Cloud"
#   api_key    = confluent_api_key.billing_export.id
#   api_secret = confluent_api_key.billing_export.secret
# }

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "organization_id" {
  value = data.confluent_organization.current.id
}

output "service_account_id" {
  value = confluent_service_account.billing_export.id
}

output "api_key" {
  description = "Confluent Cloud API key ID."
  value       = confluent_api_key.billing_export.id
}

output "api_secret" {
  description = "Confluent Cloud API key secret."
  value       = confluent_api_key.billing_export.secret
  sensitive   = true
}
