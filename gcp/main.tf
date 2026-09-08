terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }

    # Costory registration (optional). Uncomment to grant Costory read access
    # and create the datasource. The Cloud Billing export toggle itself has
    # no Terraform resource — enable it in the console after apply.
    # costory = {
    #   source  = "costory-io/costory"
    #   version = "~> 0.2"
    # }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "project_id" {
  type        = string
  description = "GCP project that hosts the BigQuery billing dataset (not necessarily a workload project)."
}

variable "dataset_id" {
  type        = string
  description = "BigQuery dataset ID for detailed usage cost. Must be US or EU multi-region for this export."
  default     = "billing_export"
}

variable "location" {
  type        = string
  description = "Dataset location. Detailed usage cost requires a US or EU multi-region."
  default     = "EU"
}

variable "billing_account_id" {
  type        = string
  description = "Cloud Billing account ID (XXXXXX-XXXXXX-XXXXXX). Used to print the expected table name. The export toggle is still console-only."
}

variable "reader_members" {
  type        = list(string)
  description = "IAM members (user:, group:, serviceAccount:) granted BigQuery Data Viewer + Metadata Viewer on the dataset. Empty by default."
  default     = []
}

# variable "costory_api_token" {
#   type        = string
#   description = "Costory API token."
#   sensitive   = true
# }

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

provider "google" {
  project = var.project_id
}

# provider "costory" {
#   token = var.costory_api_token
# }

# data "costory_service_account" "current" {}

# -----------------------------------------------------------------------------
# Expected table IDs (Google creates these after you enable the export)
# -----------------------------------------------------------------------------
# Hyphens in the billing account ID become underscores in the table name.
# There is no google_billing_account_export (or equivalent) resource. The
# dataset is the only part Terraform can create. See README.

locals {
  billing_account_table_suffix = replace(var.billing_account_id, "-", "_")
  expected_detailed_table_id   = "gcp_billing_export_resource_v1_${local.billing_account_table_suffix}"
  expected_standard_table_id   = "gcp_billing_export_v1_${local.billing_account_table_suffix}"
}

# -----------------------------------------------------------------------------
# Step 1 — BigQuery dataset (destination for Detailed usage cost)
# -----------------------------------------------------------------------------
# Standard usage cost is a summary. FinOps needs Detailed usage cost
# (resource IDs, labels). Enable that export in Billing > Billing export
# after apply, pointing at this project + dataset.

resource "google_bigquery_dataset" "billing_export" {
  project     = var.project_id
  dataset_id  = var.dataset_id
  location    = var.location
  description = "Destination for Cloud Billing detailed usage cost. Enable the export in the Billing console — there is no Terraform resource for the toggle."

  delete_contents_on_destroy = false
}

# -----------------------------------------------------------------------------
# Step 2 — Optional reader IAM (any FinOps tool / analyst group)
# -----------------------------------------------------------------------------

resource "google_bigquery_dataset_iam_member" "data_viewer" {
  for_each   = toset(var.reader_members)
  project    = var.project_id
  dataset_id = google_bigquery_dataset.billing_export.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = each.value
}

resource "google_bigquery_dataset_iam_member" "metadata_viewer" {
  for_each   = toset(var.reader_members)
  project    = var.project_id
  dataset_id = google_bigquery_dataset.billing_export.dataset_id
  role       = "roles/bigquery.metadataViewer"
  member     = each.value
}

# -----------------------------------------------------------------------------
# Costory — grant read access and register the datasource
# Uncomment this block if you want Terraform to wire Costory as well.
# -----------------------------------------------------------------------------

# locals {
#   costory_bq_roles = toset([
#     "roles/bigquery.dataViewer",
#     "roles/bigquery.metadataViewer",
#   ])
# }
#
# resource "google_bigquery_dataset_iam_member" "costory" {
#   for_each   = local.costory_bq_roles
#   project    = var.project_id
#   dataset_id = google_bigquery_dataset.billing_export.dataset_id
#   role       = each.key
#   member     = "serviceAccount:${data.costory_service_account.current.service_account}"
# }
#
# resource "costory_billing_datasource_gcp" "main" {
#   name                = "GCP Billing Export"
#   bq_uri              = "${var.project_id}.${var.dataset_id}.${local.expected_detailed_table_id}"
#   is_detailed_billing = true
#   depends_on          = [google_bigquery_dataset_iam_member.costory]
# }

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "project_id" {
  value = var.project_id
}

output "dataset_id" {
  value = google_bigquery_dataset.billing_export.dataset_id
}

output "dataset_location" {
  value = google_bigquery_dataset.billing_export.location
}

output "expected_detailed_table_id" {
  description = "Table Google creates after you enable Detailed usage cost in the Billing console."
  value       = local.expected_detailed_table_id
}

output "expected_standard_table_id" {
  description = "Table Google creates if you also enable Standard usage cost. Prefer detailed."
  value       = local.expected_standard_table_id
}

output "console_billing_export_url" {
  description = "Billing console page where you enable the export (no Terraform resource exists)."
  value       = "https://console.cloud.google.com/billing/${var.billing_account_id}/export"
}
