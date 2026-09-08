terraform {
  required_version = ">= 1.5"

  # Costory registration (optional). Cursor Admin API keys are created in the
  # dashboard — there is no Terraform resource for that key.
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

variable "cursor_admin_api_key" {
  type        = string
  description = "Cursor Admin API key (crsr_…). Create it at cursor.com/dashboard → API Keys."
  sensitive   = true
}

variable "datasource_name" {
  type        = string
  description = "Display name if you register this feed in Costory."
  default     = "Cursor Billing"
}

# variable "costory_api_token" {
#   type        = string
#   description = "Costory API token."
#   sensitive   = true
# }

# -----------------------------------------------------------------------------
# Costory — register the Cursor billing datasource
# Uncomment the provider block above, costory_api_token, and this resource.
# -----------------------------------------------------------------------------

# provider "costory" {
#   token = var.costory_api_token
# }

# resource "costory_billing_datasource_cursor" "main" {
#   name          = var.datasource_name
#   admin_api_key = var.cursor_admin_api_key
# }

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "admin_api_key_hint" {
  description = "Call POST https://api.cursor.com/teams/filtered-usage-events with Basic auth (key as username)."
  value       = "Set CURSOR_ADMIN_API_KEY and see cursor/README.md"
}
