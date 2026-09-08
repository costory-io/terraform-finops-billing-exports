terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }

    # Costory registration (optional). Uncomment to create the datasource in Costory.
    # costory = {
    #   source  = "costory-io/costory"
    #   version = "~> 0.2"
    # }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

# variable "costory_api_token" {
#   type        = string
#   description = "Costory API token."
#   sensitive   = true
# }

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID that owns the Cost Management exports."
}

variable "location" {
  type        = string
  description = "Azure region for the resource group and storage account."
  default     = "West Europe"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group that holds the export storage account."
  default     = "billing-cost-exports"
}

variable "storage_account_name_prefix" {
  type        = string
  description = "Prefix for the storage account name. A random suffix is appended (Azure names must be globally unique)."
  default     = "costexports"
}

variable "sas_token_validity_days" {
  type        = number
  description = "How long the read/list SAS token stays valid."
  default     = 900
}

variable "backfill_month_count" {
  type        = number
  description = "Number of past calendar months to export when run_backfill is true."
  default     = 12
}

variable "run_backfill" {
  type        = bool
  description = "Set true to trigger one-off historical export runs: terraform apply -var='run_backfill=true'"
  default     = false
}

variable "enable_focus" {
  type        = bool
  description = "Also create a daily FOCUS 1.2-preview Parquet export. Not a substitute for Actual + Amortized — FOCUS does not amortize correctly yet."
  default     = false
}

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# provider "costory" {
#   token = var.costory_api_token
# }

# -----------------------------------------------------------------------------
# Step 1 — Resource group + storage account + container
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "cost_exports" {
  name     = var.resource_group_name
  location = var.location
}

resource "random_string" "storage_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_storage_account" "cost_exports" {
  name                     = "${var.storage_account_name_prefix}${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.cost_exports.name
  location                 = azurerm_resource_group.cost_exports.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_container" "billing" {
  name               = "billing-exports"
  storage_account_id = azurerm_storage_account.cost_exports.id
}

# -----------------------------------------------------------------------------
# Step 2 — Daily Cost Management exports (actual + amortized)
# -----------------------------------------------------------------------------
# azurerm Cost Management export resources do not expose the latest API
# (Parquet, partitionData, exports/run backfill). azapi does.
#
# Both native types are required. FOCUS (FocusCost) does not correctly output
# amortized costs yet, so it is not a substitute.
#
#   - ActualCost     = cash/invoice view
#   - AmortizedCost  = reservations and savings plans spread over the term
#
# Azure restates the in-progress month until it closes, so the schedule is
# daily MonthToDate. partitionData = true is the better blob layout; files
# land under {rootFolderPath}/{exportName}/.

resource "time_static" "export_start" {}

locals {
  actuals_export_name   = "actuals-${random_string.storage_suffix.result}"
  amortized_export_name = "amortized-${random_string.storage_suffix.result}"
  focus_export_name     = "focus-${random_string.storage_suffix.result}"
}

resource "azapi_resource" "actuals" {
  type = "Microsoft.CostManagement/exports@2025-03-01"
  name = local.actuals_export_name
  # Scope of costs in the file. Subscription = this subscription only.
  # Billing account / enrollment = full invoice, but unused RI/SP rows often
  # have empty SubscriptionId/ResourceId. Do not use management group (usage
  # only, no amortized). See README "Export scope".
  parent_id = "/subscriptions/${var.subscription_id}"

  body = {
    properties = {
      definition = {
        type      = "ActualCost"
        timeframe = "MonthToDate"
        dataSet = {
          granularity = "Daily"
        }
      }
      schedule = {
        status     = "Active"
        recurrence = "Daily"
        recurrencePeriod = {
          from = time_static.export_start.rfc3339
          to   = "2099-01-01T00:00:00Z"
        }
      }
      format        = "Parquet"
      partitionData = true
      deliveryInfo = {
        destination = {
          container      = azurerm_storage_container.billing.name
          resourceId     = azurerm_storage_account.cost_exports.id
          rootFolderPath = "actuals"
        }
      }
    }
  }
}

resource "azapi_resource" "amortized" {
  type      = "Microsoft.CostManagement/exports@2025-03-01"
  name      = local.amortized_export_name
  parent_id = "/subscriptions/${var.subscription_id}" # same scope as actuals; see README "Export scope"

  body = {
    properties = {
      definition = {
        type      = "AmortizedCost"
        timeframe = "MonthToDate"
        dataSet = {
          granularity = "Daily"
        }
      }
      schedule = {
        status     = "Active"
        recurrence = "Daily"
        recurrencePeriod = {
          from = time_static.export_start.rfc3339
          to   = "2099-01-01T00:00:00Z"
        }
      }
      format        = "Parquet"
      partitionData = true
      deliveryInfo = {
        destination = {
          container      = azurerm_storage_container.billing.name
          resourceId     = azurerm_storage_account.cost_exports.id
          rootFolderPath = "amortized"
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Optional FOCUS 1.2-preview (same container, different folder)
# -----------------------------------------------------------------------------
# Not a substitute for Actual + Amortized. FOCUS does not correctly output
# amortized costs yet. Keep the two native exports; add this for the schema.

resource "azapi_resource" "focus" {
  count     = var.enable_focus ? 1 : 0
  type      = "Microsoft.CostManagement/exports@2025-03-01"
  name      = local.focus_export_name
  parent_id = "/subscriptions/${var.subscription_id}"

  body = {
    properties = {
      definition = {
        type      = "FocusCost"
        timeframe = "MonthToDate"
        dataSet = {
          granularity = "Daily"
          configuration = {
            dataVersion = "1.2-preview"
          }
        }
      }
      schedule = {
        status     = "Active"
        recurrence = "Daily"
        recurrencePeriod = {
          from = time_static.export_start.rfc3339
          to   = "2099-01-01T00:00:00Z"
        }
      }
      format                = "Parquet"
      partitionData         = true
      dataOverwriteBehavior = "OverwritePreviousReport"
      deliveryInfo = {
        destination = {
          container      = azurerm_storage_container.billing.name
          resourceId     = azurerm_storage_account.cost_exports.id
          rootFolderPath = "focus"
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Step 3 — Optional historical backfill
# -----------------------------------------------------------------------------
# Scheduled exports only write going forward. The exports/run action can pull
# one calendar month at a time. After a successful backfill apply, set
# run_backfill=false (or comment out the azapi_resource_action blocks)
# so later applies do not re-trigger the same months.

locals {
  absolute_month = tonumber(formatdate("YYYY", plantimestamp())) * 12 + tonumber(formatdate("M", plantimestamp())) - 1

  backfill_months = [
    for i in range(1, var.backfill_month_count + 1) : format(
      "%04d-%02d",
      floor((local.absolute_month - i) / 12),
      (local.absolute_month - i) % 12 + 1,
    )
  ]

  backfill_ranges = {
    for m in local.backfill_months : m => {
      from = "${m}-01T00:00:00Z"
      to = "${formatdate(
        "YYYY-MM-DD",
        timeadd(
          format(
            "%04d-%02d-01T00:00:00Z",
            tonumber(split("-", m)[1]) == 12 ? tonumber(split("-", m)[0]) + 1 : tonumber(split("-", m)[0]),
            tonumber(split("-", m)[1]) == 12 ? 1 : tonumber(split("-", m)[1]) + 1,
          ),
          "-24h",
        ),
      )}T00:00:00Z"
    }
  }
}

resource "azapi_resource_action" "backfill_actuals" {
  for_each = var.run_backfill ? local.backfill_ranges : {}

  type        = "Microsoft.CostManagement/exports@2025-03-01"
  resource_id = azapi_resource.actuals.id
  action      = "run"
  method      = "POST"
  when        = "apply"

  body = {
    timePeriod = {
      from = each.value.from
      to   = each.value.to
    }
  }
}

resource "azapi_resource_action" "backfill_amortized" {
  for_each = var.run_backfill ? local.backfill_ranges : {}

  type        = "Microsoft.CostManagement/exports@2025-03-01"
  resource_id = azapi_resource.amortized.id
  action      = "run"
  method      = "POST"
  when        = "apply"

  body = {
    timePeriod = {
      from = each.value.from
      to   = each.value.to
    }
  }
}

resource "azapi_resource_action" "backfill_focus" {
  for_each = var.run_backfill && var.enable_focus ? local.backfill_ranges : {}

  type        = "Microsoft.CostManagement/exports@2025-03-01"
  resource_id = azapi_resource.focus[0].id
  action      = "run"
  method      = "POST"
  when        = "apply"

  body = {
    timePeriod = {
      from = each.value.from
      to   = each.value.to
    }
  }
}

# -----------------------------------------------------------------------------
# Step 4 — Read/list SAS for any tool that needs to pull the blobs
# -----------------------------------------------------------------------------
# Easiest copy-paste. A cleaner production setup is federated identity
# (Entra ID / workload identity) when the consuming tool supports it.

resource "time_static" "sas_start" {}

data "azurerm_storage_account_sas" "billing" {
  connection_string = azurerm_storage_account.cost_exports.primary_connection_string
  https_only        = true
  signed_version    = "2022-11-02"

  start  = time_static.sas_start.rfc3339
  expiry = timeadd(time_static.sas_start.rfc3339, "${var.sas_token_validity_days * 24}h")

  resource_types {
    service   = false
    container = true
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  permissions {
    read    = true
    write   = false
    delete  = false
    list    = true
    add     = false
    create  = false
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}

locals {
  blob_endpoint_with_sas = "${azurerm_storage_account.cost_exports.primary_blob_endpoint}${azurerm_storage_container.billing.name}${data.azurerm_storage_account_sas.billing.sas}"
}

# -----------------------------------------------------------------------------
# Costory — register the Azure billing datasource
# Uncomment this block if you want Terraform to wire Costory as well.
# -----------------------------------------------------------------------------

# resource "costory_billing_datasource_azure" "main" {
#   name                 = "Azure Production"
#   sas_url              = local.blob_endpoint_with_sas
#   storage_account_name = azurerm_storage_account.cost_exports.name
#   container_name       = azurerm_storage_container.billing.name
#   actuals_path         = "actuals/${local.actuals_export_name}"
#   amortized_path       = "amortized/${local.amortized_export_name}"
# }

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "resource_group_name" {
  value = azurerm_resource_group.cost_exports.name
}

output "storage_account_name" {
  value = azurerm_storage_account.cost_exports.name
}

output "storage_container_name" {
  value = azurerm_storage_container.billing.name
}

output "actuals_path" {
  description = "Prefix for actual-cost Parquet files."
  value       = "actuals/${local.actuals_export_name}"
}

output "amortized_path" {
  description = "Prefix for amortized-cost Parquet files."
  value       = "amortized/${local.amortized_export_name}"
}

output "focus_path" {
  description = "Prefix for FOCUS 1.2-preview Parquet files, or null when enable_focus is false."
  value       = var.enable_focus ? "focus/${local.focus_export_name}" : null
}

output "sas_token" {
  value     = data.azurerm_storage_account_sas.billing.sas
  sensitive = true
}

output "blob_endpoint_with_sas" {
  description = "Full blob endpoint URL with SAS token for reading billing exports."
  value       = local.blob_endpoint_with_sas
  sensitive   = true
}

output "sas_token_expiry" {
  value = timeadd(time_static.sas_start.rfc3339, "${var.sas_token_validity_days * 24}h")
}
