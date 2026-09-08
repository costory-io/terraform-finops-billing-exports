# AWS CUR 2.0 billing export with Terraform

Terraform for an **AWS Cost and Usage Report 2.0** (CUR 2.0) via [BCM Data Exports](https://docs.aws.amazon.com/cur/latest/userguide/what-is-data-exports.html). It creates the S3 bucket, the bucket policy AWS Billing needs, and an hourly Parquet export with resource IDs, split cost allocation, and IAM principal (Bedrock) data.

Use this as the source of truth for AWS spend in Athena or any FinOps platform.

## What this stack creates

1. Private S3 bucket `{s3_name}-{account_id}`.
2. Bucket policy that allows `billingreports.amazonaws.com` and `bcm-data-exports.amazonaws.com` to write objects.
3. `aws_bcmdataexports_export` — CUR 2.0, hourly, Parquet, overwrite, full column list.
4. Optional FOCUS 1.2 (`enable_focus=true`) in the same bucket under `focus/`.

## CUR 1.0 vs CUR 2.0

Do not use `aws_cur_report_definition` (CUR 1.0). CUR 2.0 is BCM Data Exports (`aws_bcmdataexports_export`): a SQL column list, Parquet, and the flags below. CUR 1.0 is less detailed and is not recommended for new FinOps feeds.

## Why these CUR settings

| Setting | Value | Why |
| --- | --- | --- |
| Report type | CUR 2.0 (BCM Data Exports) | CUR 1.0 is less detailed and not recommended |
| Granularity | Hourly | Required for EKS / ECS split cost allocation |
| `INCLUDE_RESOURCES` | `TRUE` | Resource-level line items |
| `INCLUDE_SPLIT_COST_ALLOCATION_DATA` | `TRUE` | Pod- and task-level cost (`split_line_item_*`) |
| `INCLUDE_IAM_PRINCIPAL_DATA` | `TRUE` | Caller identity on Bedrock inference (`line_item_iam_principal`) |
| Format | Parquet + overwrite | One latest partition per billing period |

The SQL `SELECT` is the full CUR 2.0 column list. Narrowing it drops tags, split line items, savings plans, or `line_item_iam_principal`.

Enabling a flag on the export is not enough for split cost or Bedrock tags. Also opt in under **Cost Management preferences** / cost allocation tags (`aws:eks:*`, `aws:ecs:*`, and any `iamPrincipal/` tags you care about) or those columns stay empty.

## Timeline — options to turn on

AWS keeps adding allocation columns to CUR 2.0. This stack turns the current ones on so you do not discover them a year later.

| When | What shipped | What this export sets |
| --- | --- | --- |
| Apr 2023 | [Split cost allocation for ECS tasks and Batch jobs](https://aws.amazon.com/about-aws/whats-new/2023/04/aws-split-cost-allocation-data-amazon-ecs-batch/) | Shared EC2 billed at the task, not only the instance |
| Nov 2023 | [Data Exports / CUR 2.0](https://aws.amazon.com/blogs/aws-cloud-financial-management/introducing-data-exports-for-billing-and-cost-management/) | `aws_bcmdataexports_export` instead of legacy `aws_cur_report_definition` |
| Apr 2024 | [Split cost allocation for EKS](https://aws.amazon.com/blogs/aws-cloud-financial-management/improve-cost-visibility-of-amazon-eks-with-aws-split-cost-allocation-data/) | Pod-level CPU/memory split; `aws:eks:namespace`, `aws:eks:deployment`, … |
| Apr 8, 2026 | [IAM principal / Bedrock caller identity](https://docs.aws.amazon.com/cur/latest/userguide/table-dictionary-cur2.html) | `INCLUDE_IAM_PRINCIPAL_DATA = TRUE` → `line_item_iam_principal` |

### Kubernetes split cost allocation

Without split data, an EKS node is one EC2 line item. With it, CUR adds `split_line_item_*` rows so you can charge back by namespace, workload, or pod.

This export sets `INCLUDE_SPLIT_COST_ALLOCATION_DATA = TRUE` and **hourly** granularity (daily is too coarse for pod lifetimes). You still have to:

1. Opt in to split cost allocation on the **payer** Cost Management preferences page (ECS, EKS, or both; for EKS pick requests vs Prometheus vs Container Insights).
2. Keep the `aws:eks:*` cost allocation tags enabled.

Data is not retroactive. It shows up for the current month after you opt in (often 24 hours).

### Bedrock cost allocation (`line_item_iam_principal`)

Bedrock inference is usually one model ARN shared by many apps. **IAM principal data** records the calling user or role on each inference line item so you can allocate by team without joining CloudTrail.

- Terraform: `INCLUDE_IAM_PRINCIPAL_DATA = TRUE` (already on).
- Column: `line_item_iam_principal` (IAM or STS ARN).
- If you activate tags on those principals as cost allocation tags, they appear in `tags` with an `iamPrincipal/` prefix.

AWS only populates the new columns **from 8 April 2026**. Enabling the flag does not backfill older Bedrock spend. File size can grow when many callers hit the same model.

## Optional FOCUS 1.2

FOCUS (`FOCUS_1_2_AWS`) is a **standard schema**, not a replacement for CUR 2.0. This stack keeps CUR as the source of truth. Set `enable_focus=true` to also write hourly Parquet under `focus/` in the same bucket.

```bash
terraform apply -var='enable_focus=true'
```

AWS limits you to **2 FOCUS 1.2 exports per account**. The `SELECT` is the FOCUS 1.2 column list plus `x_Discounts`, `x_Operation`, `x_ServiceCode`. Time granularity is hourly so it can sit next to CUR.

Do not drop CUR 2.0 for FOCUS: split cost allocation (`split_line_item_*`) and `line_item_iam_principal` live on CUR.

## Prerequisites

- Terraform >= 1.5
- AWS credentials that can create S3 buckets, bucket policies, and BCM Data Exports
- Apply in the **payer / management account** if you want organization-wide CUR

BCM Data Exports are created in `us-east-1`. The bucket can live in another region (`aws_region`).

## Apply

```bash
cd aws
terraform init
terraform apply
```

Optional variables:

| Variable | Default | Description |
| --- | --- | --- |
| `s3_name` | `billing-data-exports` | Bucket name prefix |
| `s3_prefix` | `cur` | Object prefix |
| `aws_region` | `us-east-1` | Bucket region |
| `enable_focus` | `false` | Also create FOCUS 1.2 in the same bucket |
| `focus_s3_prefix` | `focus` | Object prefix for FOCUS |

## Outputs

- `bucket_name` — S3 bucket that receives Parquet files
- `prefix` — CUR object prefix
- `export_name` — CUR 2.0 BCM Data Exports name
- `focus_export_name`, `focus_prefix` — set when `enable_focus=true`

The first export can take up to 12 hours.

## Billing API

CUR 2.0 is a **push export**, not a pull API. AWS writes Parquet to the S3 bucket this stack creates. There is no REST endpoint that returns the same line items.

| Step | API | What it does |
| --- | --- | --- |
| Create / update the export | [BCM Data Exports `CreateExport`](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_bcm-data-exports_CreateExport.html) (`aws_bcmdataexports_export`) | Hourly CUR 2.0 into S3 (optional second export: `FOCUS_1_2_AWS`) |
| Read the files | S3 `ListObjects` + `GetObject` on `{bucket}/{prefix}/` | Parquet partitions (overwrite, one latest set per billing period) |

Do not use Cost Explorer or the Billing API as a substitute. Those are summaries; CUR 2.0 is the line-item feed.

## Data output

Hourly Parquet. Column names match the [CUR 2.0 table dictionary](https://docs.aws.amazon.com/cur/latest/userguide/table-dictionary-cur2.html). The Terraform `SELECT` is the **full** column list. Fields a FinOps converter typically reads:

| Column | Type | Notes |
| --- | --- | --- |
| `bill_billing_period_start_date`, `bill_billing_period_end_date` | timestamp | Invoice month |
| `bill_payer_account_id` | string | Payer / management account |
| `line_item_usage_start_date`, `line_item_usage_end_date` | timestamp | Hour grain |
| `line_item_line_item_type` | string | Usage, Discount, Tax, … |
| `line_item_unblended_cost`, `line_item_net_unblended_cost` | double | Cash / net cash |
| `line_item_usage_amount` | double | Quantity |
| `line_item_usage_account_id`, `line_item_usage_account_name` | string | Linked account |
| `line_item_product_code`, `line_item_usage_type`, `line_item_resource_id` | string | Service / SKU / resource |
| `line_item_iam_principal` | string | Bedrock caller (from 8 Apr 2026) |
| `pricing_unit`, `product_sku`, `product_region_code`, `product_product_family` | string | Pricing dims |
| `savings_plan_*`, `reservation_*` | mixed | Commitment amortization |
| `resource_tags`, `product`, `cost_category` | map | Key/value structs |

Split-cost rows add `split_line_item_*` (pod / task allocation). See the [CUR 2.0 dictionary](https://docs.aws.amazon.com/cur/latest/userguide/table-dictionary-cur2.html) for every column in the export.

## Official docs

- [What is Data Exports?](https://docs.aws.amazon.com/cur/latest/userguide/what-is-data-exports.html)
- [aws_bcmdataexports_export](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bcmdataexports_export)
- [Split cost allocation data](https://docs.aws.amazon.com/cur/latest/userguide/split-cost-allocation-data.html)
- [IAM principal cost allocation (Bedrock)](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/iam-principal-cost-allocation.html)
- [CUR 2.0 table dictionary](https://docs.aws.amazon.com/cur/latest/userguide/table-dictionary-cur2.html)
- [FOCUS 1.2 with AWS columns](https://docs.aws.amazon.com/cur/latest/userguide/table-dictionary-focus-1-2-aws.html)
