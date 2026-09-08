terraform {
  required_version = ">= 1.5"

  # Costory registration (optional). Anthropic keys are created in the Claude
  # Console / claude.ai — there is no Terraform resource for those keys.
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

variable "anthropic_admin_api_key" {
  type        = string
  description = "Claude Console Admin API key (sk-ant-admin-…). Create it under Admin keys. Not interchangeable with the Analytics key."
  sensitive   = true
  default     = null
}

variable "anthropic_analytics_api_key" {
  type        = string
  description = "claude.ai Enterprise Analytics API key (read:analytics). Created by the primary owner under Organization settings → API."
  sensitive   = true
  default     = null
}

variable "anthropic_account_name" {
  type        = string
  description = "Display label for the Claude Enterprise org (not sent to Anthropic)."
  default     = ""
}

variable "datasource_name" {
  type        = string
  description = "Display name if you register the Console Admin feed in Costory."
  default     = "Anthropic Billing"
}

variable "enterprise_datasource_name" {
  type        = string
  description = "Display name if you register the Claude Enterprise Analytics feed in Costory."
  default     = "Anthropic Claude AI"
}

# variable "costory_api_token" {
#   type        = string
#   description = "Costory API token."
#   sensitive   = true
# }

# -----------------------------------------------------------------------------
# Costory — register Anthropic billing datasources
# Uncomment the provider block above, costory_api_token, and the resource(s).
# Console Admin and Claude Enterprise Analytics are separate datasources.
# -----------------------------------------------------------------------------

# provider "costory" {
#   token = var.costory_api_token
# }

# resource "costory_billing_datasource_anthropic" "console" {
#   name          = var.datasource_name
#   admin_api_key = var.anthropic_admin_api_key
# }

# Claude Enterprise Analytics (type ANTHROPIC_CLAUDE_AI). Connect the
# analytics key in the Costory UI if your provider version has no resource yet.
# resource "costory_billing_datasource_anthropic_claude_ai" "enterprise" {
#   name              = var.enterprise_datasource_name
#   analytics_api_key = var.anthropic_analytics_api_key
#   account_name      = var.anthropic_account_name
# }

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "admin_api_key_hint" {
  description = "Claude Console: GET /v1/organizations/cost_report with x-api-key (Admin key)."
  value       = "Set ANTHROPIC_ADMIN_KEY and see anthropic/README.md"
}

output "analytics_api_key_hint" {
  description = "Claude Enterprise: GET /v1/organizations/analytics/user_cost_report with x-api-key (Analytics key)."
  value       = "Set ANTHROPIC_ANALYTICS_KEY and see anthropic/README.md"
}
