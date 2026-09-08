terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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

variable "s3_name" {
  type        = string
  description = "Base name for the CUR 2.0 bucket. The account ID is appended."
  default     = "billing-data-exports"
}

variable "s3_prefix" {
  type        = string
  description = "S3 prefix where AWS writes CUR 2.0 Parquet files."
  default     = "cur"
}

variable "aws_region" {
  type        = string
  description = "Region for the export bucket. CUR 2.0 / BCM Data Exports are created in us-east-1 regardless."
  default     = "us-east-1"
}

variable "enable_focus" {
  type        = bool
  description = "Also create a FOCUS 1.2 (FOCUS_1_2_AWS) hourly Parquet export in the same bucket. CUR 2.0 stays the FinOps source of truth. AWS limits you to 2 FOCUS 1.2 exports per account."
  default     = false
}

variable "focus_s3_prefix" {
  type        = string
  description = "S3 prefix for the optional FOCUS 1.2 export."
  default     = "focus"
}

# variable "costory_api_token" {
#   type        = string
#   description = "Costory API token."
#   sensitive   = true
# }

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

# provider "costory" {
#   token = var.costory_api_token
# }

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# data "costory_service_account" "current" {}

# -----------------------------------------------------------------------------
# CUR 2.0 settings
# -----------------------------------------------------------------------------
# Hourly granularity + split cost allocation is required for EKS/ECS pod-level
# and task-level cost. INCLUDE_IAM_PRINCIPAL_DATA adds line_item_iam_principal
# for Bedrock caller identity (columns populate from 2026-04-08). Parquet +
# overwrite keeps a single latest partition per billing period.

locals {
  account_id      = data.aws_caller_identity.current.account_id
  cur_bucket_name = "${var.s3_name}-${local.account_id}"
  cur_export_name = "${var.s3_name}-data-exports"

  # BCM Data Exports and legacy CUR both need a source ARN condition on the
  # bucket policy. See https://github.com/hashicorp/terraform-provider-aws/issues/43978
  cur_definition_source_arn = "arn:${data.aws_partition.current.partition}:cur:us-east-1:${local.account_id}:definition/*"
  bcm_export_source_arn     = "arn:${data.aws_partition.current.partition}:bcm-data-exports:us-east-1:${local.account_id}:export/*"

  cur_table_configurations = {
    COST_AND_USAGE_REPORT = {
      INCLUDE_RESOURCES                     = "TRUE"
      INCLUDE_SPLIT_COST_ALLOCATION_DATA    = "TRUE"
      TIME_GRANULARITY                      = "HOURLY"
      INCLUDE_MANUAL_DISCOUNT_COMPATIBILITY = "FALSE"
      INCLUDE_CAPACITY_RESERVATION_DATA     = "TRUE"
      BILLING_VIEW_ARN                      = "arn:${data.aws_partition.current.partition}:billing::${local.account_id}:billingview/primary"
      INCLUDE_IAM_PRINCIPAL_DATA            = "TRUE"
    }
  }

  # Full CUR 2.0 column set. Narrowing this list drops fields FinOps tools need
  # (resource tags, split line items, savings plans, reservations).
  cur_query_statement = <<-EOT
SELECT bill_bill_type, bill_billing_entity, bill_billing_period_end_date, bill_billing_period_start_date, bill_invoice_id, bill_invoicing_entity, bill_payer_account_id, bill_payer_account_name, capacity_reservation_capacity_reservation_arn, capacity_reservation_capacity_reservation_status, capacity_reservation_capacity_reservation_type, cost_category, discount, discount_bundled_discount, discount_total_discount, identity_line_item_id, identity_time_interval, line_item_availability_zone, line_item_blended_cost, line_item_blended_rate, line_item_currency_code, line_item_iam_principal, line_item_legal_entity, line_item_line_item_description, line_item_line_item_type, line_item_net_unblended_cost, line_item_net_unblended_rate, line_item_normalization_factor, line_item_normalized_usage_amount, line_item_operation, line_item_product_code, line_item_resource_id, line_item_tax_type, line_item_unblended_cost, line_item_unblended_rate, line_item_usage_account_id, line_item_usage_account_name, line_item_usage_amount, line_item_usage_end_date, line_item_usage_start_date, line_item_usage_type, line_item_user_identifier, pricing_currency, pricing_lease_contract_length, pricing_offering_class, pricing_public_on_demand_cost, pricing_public_on_demand_rate, pricing_purchase_option, pricing_rate_code, pricing_rate_id, pricing_term, pricing_unit, product, product_comment, product_fee_code, product_fee_description, product_from_location, product_from_location_type, product_from_region_code, product_instance_family, product_instance_type, product_instancesku, product_location, product_location_type, product_operation, product_pricing_unit, product_product_family, product_region_code, product_servicecode, product_sku, product_to_location, product_to_location_type, product_to_region_code, product_usagetype, reservation_amortized_upfront_cost_for_usage, reservation_amortized_upfront_fee_for_billing_period, reservation_availability_zone, reservation_effective_cost, reservation_end_time, reservation_modification_status, reservation_net_amortized_upfront_cost_for_usage, reservation_net_amortized_upfront_fee_for_billing_period, reservation_net_effective_cost, reservation_net_recurring_fee_for_usage, reservation_net_unused_amortized_upfront_fee_for_billing_period, reservation_net_unused_recurring_fee, reservation_net_upfront_value, reservation_normalized_units_per_reservation, reservation_number_of_reservations, reservation_recurring_fee_for_usage, reservation_reservation_a_r_n, reservation_start_time, reservation_subscription_id, reservation_total_reserved_normalized_units, reservation_total_reserved_units, reservation_units_per_reservation, reservation_unused_amortized_upfront_fee_for_billing_period, reservation_unused_normalized_unit_quantity, reservation_unused_quantity, reservation_unused_recurring_fee, reservation_upfront_value, resource_tags, savings_plan_amortized_upfront_commitment_for_billing_period, savings_plan_end_time, savings_plan_instance_type_family, savings_plan_net_amortized_upfront_commitment_for_billing_period, savings_plan_net_recurring_commitment_for_billing_period, savings_plan_net_savings_plan_effective_cost, savings_plan_offering_type, savings_plan_payment_option, savings_plan_purchase_term, savings_plan_recurring_commitment_for_billing_period, savings_plan_region, savings_plan_savings_plan_a_r_n, savings_plan_savings_plan_effective_cost, savings_plan_savings_plan_rate, savings_plan_start_time, savings_plan_total_commitment_to_date, savings_plan_used_commitment, split_line_item_actual_usage, split_line_item_net_split_cost, split_line_item_net_unused_cost, split_line_item_parent_resource_id, split_line_item_public_on_demand_split_cost, split_line_item_public_on_demand_unused_cost, split_line_item_reserved_usage, split_line_item_split_cost, split_line_item_split_usage, split_line_item_split_usage_ratio, split_line_item_unused_cost, tags FROM COST_AND_USAGE_REPORT
EOT
}

# -----------------------------------------------------------------------------
# Step 1 — Destination bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "cur" {
  bucket = local.cur_bucket_name
}

resource "aws_s3_bucket_public_access_block" "cur" {
  bucket = aws_s3_bucket.cur.id

  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# Step 2 — Allow AWS Billing / BCM Data Exports to write into the bucket
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "cur_bucket" {
  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "billingreports.amazonaws.com",
        "bcm-data-exports.amazonaws.com",
      ]
    }
    actions = [
      "s3:PutObject",
      "s3:GetBucketPolicy",
    ]
    resources = [
      aws_s3_bucket.cur.arn,
      "${aws_s3_bucket.cur.arn}/*",
    ]
    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values = [
        local.cur_definition_source_arn,
        local.bcm_export_source_arn,
      ]
    }
    condition {
      test     = "StringLike"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "cur" {
  bucket = aws_s3_bucket.cur.id
  policy = data.aws_iam_policy_document.cur_bucket.json
}

# -----------------------------------------------------------------------------
# Step 3 — CUR 2.0 data export (BCM Data Exports)
# -----------------------------------------------------------------------------

resource "aws_bcmdataexports_export" "cur" {
  depends_on = [aws_s3_bucket_policy.cur]

  export {
    name = local.cur_export_name

    data_query {
      query_statement      = local.cur_query_statement
      table_configurations = local.cur_table_configurations
    }

    destination_configurations {
      s3_destination {
        s3_bucket = aws_s3_bucket.cur.bucket
        s3_region = var.aws_region
        s3_prefix = var.s3_prefix

        s3_output_configurations {
          compression = "PARQUET"
          format      = "PARQUET"
          output_type = "CUSTOM"
          overwrite   = "OVERWRITE_REPORT"
        }
      }
    }

    refresh_cadence {
      frequency = "SYNCHRONOUS"
    }
  }
}

# -----------------------------------------------------------------------------
# Optional FOCUS 1.2 (same bucket, different prefix)
# -----------------------------------------------------------------------------
# Not a substitute for CUR 2.0. FOCUS is the standard schema; CUR 2.0 has
# split cost allocation, IAM principal, and the full AWS column set.
# AWS quota: 2 FOCUS_1_2_AWS exports per account.

locals {
  focus_export_name     = "${var.s3_name}-focus-1-2"
  focus_query_statement = <<-EOT
SELECT AvailabilityZone, BilledCost, BillingAccountId, BillingAccountName, BillingAccountType, BillingCurrency, BillingPeriodEnd, BillingPeriodStart, CapacityReservationId, CapacityReservationStatus, ChargeCategory, ChargeClass, ChargeDescription, ChargeFrequency, ChargePeriodEnd, ChargePeriodStart, CommitmentDiscountCategory, CommitmentDiscountId, CommitmentDiscountName, CommitmentDiscountQuantity, CommitmentDiscountStatus, CommitmentDiscountType, CommitmentDiscountUnit, ConsumedQuantity, ConsumedUnit, ContractedCost, ContractedUnitPrice, EffectiveCost, InvoiceId, InvoiceIssuerName, ListCost, ListUnitPrice, PricingCategory, PricingCurrency, PricingCurrencyContractedUnitPrice, PricingCurrencyEffectiveCost, PricingCurrencyListUnitPrice, PricingQuantity, PricingUnit, ProviderName, PublisherName, RegionId, RegionName, ResourceId, ResourceName, ResourceType, ServiceCategory, ServiceName, ServiceSubcategory, SkuId, SkuMeter, SkuPriceDetails, SkuPriceId, SubAccountId, SubAccountName, SubAccountType, Tags, x_Discounts, x_Operation, x_ServiceCode FROM FOCUS_1_2_AWS
EOT
}

resource "aws_bcmdataexports_export" "focus" {
  count      = var.enable_focus ? 1 : 0
  depends_on = [aws_s3_bucket_policy.cur]

  export {
    name = local.focus_export_name

    data_query {
      query_statement = local.focus_query_statement
      table_configurations = {
        FOCUS_1_2_AWS = {
          TIME_GRANULARITY = "HOURLY"
        }
      }
    }

    destination_configurations {
      s3_destination {
        s3_bucket = aws_s3_bucket.cur.bucket
        s3_region = var.aws_region
        s3_prefix = var.focus_s3_prefix

        s3_output_configurations {
          compression = "PARQUET"
          format      = "PARQUET"
          output_type = "CUSTOM"
          overwrite   = "OVERWRITE_REPORT"
        }
      }
    }

    refresh_cadence {
      frequency = "SYNCHRONOUS"
    }
  }

  lifecycle {
    # Provider can force replacement on table_configurations.
    # https://github.com/hashicorp/terraform-provider-aws/issues/46402
    ignore_changes = [export[0].data_query[0].table_configurations]
  }
}

# -----------------------------------------------------------------------------
# Costory — grant read access and register the datasource
# Costory is hosted on GCP and assumes a web-identity IAM role in your account.
# Uncomment this block if you want Terraform to wire Costory as well.
# -----------------------------------------------------------------------------

# data "aws_iam_policy_document" "costory_read_s3" {
#   statement {
#     sid    = "Statement1"
#     effect = "Allow"
#     actions = [
#       "s3:ListBucket",
#       "s3:GetObject",
#     ]
#     resources = [
#       aws_s3_bucket.cur.arn,
#       "${aws_s3_bucket.cur.arn}/*",
#     ]
#   }
# }
#
# resource "aws_iam_policy" "costory_read_s3" {
#   name        = "Costory-read-s3-${var.s3_name}"
#   description = "Allows Costory to read the CUR S3 bucket."
#   policy      = data.aws_iam_policy_document.costory_read_s3.json
# }
#
# data "aws_iam_policy_document" "costory_federated_role_assume" {
#   statement {
#     effect = "Allow"
#     actions = [
#       "sts:AssumeRoleWithWebIdentity",
#     ]
#     principals {
#       type        = "Federated"
#       identifiers = ["accounts.google.com"]
#     }
#     condition {
#       test     = "StringEquals"
#       variable = "accounts.google.com:sub"
#       values   = data.costory_service_account.current.sub_ids
#     }
#   }
# }
#
# resource "aws_iam_role" "costory_federated_role" {
#   name               = "costory-trust-link-${var.s3_name}"
#   assume_role_policy = data.aws_iam_policy_document.costory_federated_role_assume.json
# }
#
# resource "aws_iam_role_policy_attachment" "costory_read_s3" {
#   role       = aws_iam_role.costory_federated_role.name
#   policy_arn = aws_iam_policy.costory_read_s3.arn
# }
#
# resource "costory_billing_datasource_aws" "main" {
#   name                   = "AWS CUR ${var.s3_name}"
#   bucket_name            = aws_s3_bucket.cur.bucket
#   role_arn               = aws_iam_role.costory_federated_role.arn
#   prefix                 = var.s3_prefix
#   eks_split_data_enabled = true
#   depends_on             = [aws_bcmdataexports_export.cur]
# }

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "bucket_name" {
  description = "S3 bucket that receives CUR 2.0 Parquet files."
  value       = aws_s3_bucket.cur.bucket
}

output "prefix" {
  description = "Object prefix inside the bucket."
  value       = var.s3_prefix
}

output "export_name" {
  description = "BCM Data Exports CUR 2.0 export name."
  value       = local.cur_export_name
}

output "focus_export_name" {
  description = "FOCUS 1.2 export name, or null when enable_focus is false."
  value       = var.enable_focus ? local.focus_export_name : null
}

output "focus_prefix" {
  description = "S3 prefix for FOCUS 1.2 Parquet, or null when enable_focus is false."
  value       = var.enable_focus ? var.focus_s3_prefix : null
}
