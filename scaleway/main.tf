terraform {
  required_version = ">= 1.5"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = ">= 2.50"
    }

    # Costory registration (optional). There is no costory_billing_datasource_scaleway
    # resource yet. Connect the secret key in the Costory UI after apply.
    # costory = {
    #   source  = "costory-io/costory"
    #   version = "~> 0.2"
    # }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "scaleway_access_key" {
  type        = string
  description = "Access key for the Terraform principal. Can also be SCW_ACCESS_KEY."
  sensitive   = true
}

variable "scaleway_secret_key" {
  type        = string
  description = "Secret key for the Terraform principal. Can also be SCW_SECRET_KEY."
  sensitive   = true
}

variable "organization_id" {
  type        = string
  description = "Scaleway Organization ID. Can also be SCW_DEFAULT_ORGANIZATION_ID."
}

variable "project_id" {
  type        = string
  description = "Default project for the provider. Can also be SCW_DEFAULT_PROJECT_ID."
}

variable "application_name" {
  type        = string
  description = "IAM application that will own the billing-export API key."
  default     = "billing-export"
}

# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------

provider "scaleway" {
  access_key      = var.scaleway_access_key
  secret_key      = var.scaleway_secret_key
  organization_id = var.organization_id
  project_id      = var.project_id
}

# -----------------------------------------------------------------------------
# Step 1 — IAM application
# -----------------------------------------------------------------------------

resource "scaleway_iam_application" "billing_export" {
  name            = var.application_name
  description     = "Read-only Scaleway consumption for billing exports."
  organization_id = var.organization_id
}

# -----------------------------------------------------------------------------
# Step 2 — BillingReadOnly at organization scope
# -----------------------------------------------------------------------------
# The consumption API is organization-scoped. A project-scoped rule cannot
# list invoices or consumption for the whole org.

resource "scaleway_iam_policy" "billing_export" {
  name           = "billing-export-read"
  description    = "Organization-scoped BillingReadOnly for billing exports."
  application_id = scaleway_iam_application.billing_export.id

  rule {
    organization_id      = var.organization_id
    permission_set_names = ["BillingReadOnly"]
  }
}

# -----------------------------------------------------------------------------
# Step 3 — API key
# -----------------------------------------------------------------------------
# The billing API authenticates with X-Auth-Token = secret_key.
# The access key is unused by GET /billing/v2beta1/consumptions.

resource "scaleway_iam_api_key" "billing_export" {
  application_id = scaleway_iam_application.billing_export.id
  description    = "Billing export API key"
}

# -----------------------------------------------------------------------------
# Costory — register the Scaleway billing datasource
# Not supported as a Terraform resource yet. Paste secret_key + organization_id
# in Integrations → Scaleway.
# -----------------------------------------------------------------------------

# resource "costory_billing_datasource_scaleway" "main" {
#   name            = "Scaleway"
#   secret_key      = scaleway_iam_api_key.billing_export.secret_key
#   organization_id = var.organization_id
# }

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "organization_id" {
  value = var.organization_id
}

output "application_id" {
  value = scaleway_iam_application.billing_export.id
}

output "access_key" {
  description = "IAM access key. Optional for the consumption API."
  value       = scaleway_iam_api_key.billing_export.access_key
}

output "secret_key" {
  description = "IAM secret key. Send as X-Auth-Token to GET /billing/v2beta1/consumptions."
  value       = scaleway_iam_api_key.billing_export.secret_key
  sensitive   = true
}
