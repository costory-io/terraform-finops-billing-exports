terraform {
  required_version = ">= 1.5"

  # Costory registration (optional). Elastic Cloud Organization API keys are
  # created in the console — there is no Terraform resource for that key.
  # required_providers {
  #   costory = {
  #     source  = "costory-io/costory"
  #     version = "~> 0.2"
  #   }
  # }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "elastic_cloud_api_key" {
  type        = string
  description = "Elastic Cloud Organization API key with Billing admin. Create it in the Elastic Cloud console."
  sensitive   = true
}

variable "elastic_cloud_organization_id" {
  type        = string
  description = "Elastic Cloud organization ID."
}

variable "datasource_name" {
  type        = string
  description = "Display name if you register this feed in Costory."
  default     = "Elastic Cloud Billing"
}

# variable "costory_api_token" {
#   type        = string
#   description = "Costory API token."
#   sensitive   = true
# }

# -----------------------------------------------------------------------------
# Costory — register the Elastic Cloud billing datasource
# Uncomment the provider block above, costory_api_token, and this resource.
# -----------------------------------------------------------------------------

# provider "costory" {
#   token = var.costory_api_token
# }

# resource "costory_billing_datasource_elastic_cloud" "main" {
#   name            = var.datasource_name
#   api_key         = var.elastic_cloud_api_key
#   organization_id = var.elastic_cloud_organization_id
# }

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "organization_id" {
  value = var.elastic_cloud_organization_id
}

output "api_key_hint" {
  description = "Call GET /api/v2/billing/organizations/{id}/costs/instances with Authorization: ApiKey …"
  value       = "Set EC_API_KEY and see elastic-cloud/README.md"
}
