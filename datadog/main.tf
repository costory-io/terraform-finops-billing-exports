terraform {
  required_version = ">= 1.5"

  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = ">= 3.52.0"
    }

    # Costory registration (optional). There is no costory_billing_datasource_datadog
    # resource yet. Connect the keys in the Costory UI after apply.
    # costory = {
    #   source  = "costory-io/costory"
    #   version = "~> 0.2"
    # }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "datadog_api_key" {
  type        = string
  description = "Existing Datadog API key used by Terraform to manage this org. Can also be DD_API_KEY."
  sensitive   = true
}

variable "datadog_app_key" {
  type        = string
  description = "Existing Datadog application key used by Terraform. Can also be DD_APP_KEY."
  sensitive   = true
}

variable "datadog_api_url" {
  type        = string
  description = "Datadog site API URL. US1: https://api.datadoghq.com, EU: https://api.datadoghq.eu"
  default     = "https://api.datadoghq.com"
}

variable "service_account_email" {
  type        = string
  description = "Unique email for the billing-export service account (must not already exist in the org)."
}

variable "service_account_name" {
  type        = string
  description = "Display name for the billing-export service account."
  default     = "billing-export"
}

# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
  api_url = var.datadog_api_url
}

# -----------------------------------------------------------------------------
# Step 1 — Least-privilege role
# -----------------------------------------------------------------------------
# usage_read    = product usage volumes (GET /api/v2/usage/hourly_usage)
# billing_read  = estimated + historical cost (GET /api/v2/usage/estimated_cost,
#                 GET /api/v2/usage/historical_cost)
#
# Both are required. usage_read alone cannot produce cost rows.

data "datadog_permissions" "all" {}

resource "datadog_role" "billing_export" {
  name = "billing-export-reader"

  permission {
    id = data.datadog_permissions.all.permissions.usage_read
  }

  permission {
    id = data.datadog_permissions.all.permissions.billing_read
  }
}

# -----------------------------------------------------------------------------
# Step 2 — Service account that owns the application key
# -----------------------------------------------------------------------------
# Application-key scopes can only grant a subset of the owner's permissions, so
# the service account must hold the role above.

resource "datadog_service_account" "billing_export" {
  email = var.service_account_email
  name  = var.service_account_name
  roles = [datadog_role.billing_export.id]
}

# -----------------------------------------------------------------------------
# Step 3 — Org API key + scoped application key
# -----------------------------------------------------------------------------
# Datadog billing APIs authenticate with:
#   DD-API-KEY         = org API key
#   DD-APPLICATION-KEY = user or service-account application key

resource "datadog_api_key" "billing_export" {
  name = "billing-export"
}

resource "datadog_service_account_application_key" "billing_export" {
  service_account_id = datadog_service_account.billing_export.id
  name               = "billing-export"

  scopes = [
    data.datadog_permissions.all.permissions.usage_read,
    data.datadog_permissions.all.permissions.billing_read,
  ]
}

# -----------------------------------------------------------------------------
# Costory — register the Datadog billing datasource
# Not supported as a Terraform resource yet. Paste the outputs below in
# Integrations → Datadog → Billing.
# -----------------------------------------------------------------------------

# resource "costory_billing_datasource_datadog" "main" {
#   name    = "Datadog"
#   api_key = datadog_api_key.billing_export.key
#   app_key = datadog_service_account_application_key.billing_export.key
#   site    = var.datadog_api_url
# }

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "api_key" {
  description = "Org API key (DD-API-KEY)."
  value       = datadog_api_key.billing_export.key
  sensitive   = true
}

output "application_key" {
  description = "Scoped application key (DD-APPLICATION-KEY)."
  value       = datadog_service_account_application_key.billing_export.key
  sensitive   = true
}

output "service_account_id" {
  value = datadog_service_account.billing_export.id
}

output "role_id" {
  value = datadog_role.billing_export.id
}
