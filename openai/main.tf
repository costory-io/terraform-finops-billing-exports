terraform {
  required_version = ">= 1.5"

  # Costory registration (optional). OpenAI Admin API keys are created in the
  # API Platform dashboard — there is no Terraform resource for that key.
  # There is no costory_billing_datasource_openai in older provider versions;
  # connect the key in the Costory UI if the resource is missing.
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

variable "openai_admin_api_key" {
  type        = string
  description = "OpenAI Admin API key (sk-admin-…). Create it under Organization → Admin keys."
  sensitive   = true
}

variable "datasource_name" {
  type        = string
  description = "Display name if you register this feed in Costory."
  default     = "OpenAI Billing"
}

# variable "costory_api_token" {
#   type        = string
#   description = "Costory API token."
#   sensitive   = true
# }

# -----------------------------------------------------------------------------
# Costory — register the OpenAI billing datasource
# Uncomment if your costory provider version includes this resource.
# -----------------------------------------------------------------------------

# provider "costory" {
#   token = var.costory_api_token
# }

# resource "costory_billing_datasource_openai" "main" {
#   name          = var.datasource_name
#   admin_api_key = var.openai_admin_api_key
# }

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "admin_api_key_hint" {
  description = "Call GET /v1/organization/costs with Authorization: Bearer sk-admin-…"
  value       = "Set OPENAI_ADMIN_KEY and see openai/README.md"
}
