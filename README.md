# Terraform FinOps billing exports: AWS CUR 2.0, Azure, GCP, Datadog, SaaS

Copy-paste Terraform to set up **billing exports** for FinOps: AWS CUR 2.0 (BCM Data Exports, hourly Parquet), Azure Cost Management (Actual + Amortized, optional FOCUS), GCP BigQuery detailed usage cost, Datadog, Aiven, Confluent Cloud, ClickHouse Cloud, Scaleway, Elastic Cloud, Cloudflare, Snowflake, Anthropic (Console Admin + Claude Enterprise Analytics), OpenAI, and Cursor.

Each folder is a standalone stack (`README.md` + `main.tf`): Terraform for the export or a least-privilege credential. Anthropic, OpenAI, Cursor, and Elastic Cloud have no provider resource to mint Admin / Analytics / Organization keys — console only. Folder READMEs have curl/SQL and types. This page is the catalog: **endpoint, auth, grain, fields**.

## Billing API catalog

Push exports write files (S3, Azure Blob, BigQuery). Everything else is a pull API or SQL. Do not use Cost Explorer / Cloud Billing REST as a CUR / BigQuery substitute — those are summaries.

| Provider | Endpoint | Auth | Grain | Fields |
| --- | --- | --- | --- | --- |
| [AWS CUR 2.0](aws/) | Push: BCM Data Exports → S3 `{bucket}/{prefix}/` Parquet. Read with `ListObjects` + `GetObject`. No line-item REST API. | IAM on the bucket this stack creates | Hour | `bill_payer_account_id`, `line_item_usage_start_date`, `line_item_line_item_type`, `line_item_unblended_cost`, `line_item_net_unblended_cost`, `line_item_usage_amount`, `line_item_usage_account_id`, `line_item_product_code`, `line_item_usage_type`, `line_item_resource_id`, `line_item_iam_principal`, `resource_tags`, `split_line_item_*` |
| [Azure Cost Management](azure/) | Push: `PUT {scope}/providers/Microsoft.CostManagement/exports` then blob `List`/`Get` under `actuals/` and `amortized/`. Backfill: `POST …/exports/{name}/run`. | Azure RBAC + container SAS (or federated identity) | Day (MonthToDate restated daily) | `BillingAccountId`, `UsageDateTime`, `ChargeType`, `MeterName`, `CostInUsd`, `PreTaxCost`, `Quantity`, `ResourceId`, `SubscriptionId`, `Tags`, `BenefitId` — Actual (cash) and Amortized (RI/SP spread) share the schema |
| [GCP BigQuery billing](gcp/) | Push: BigQuery table `gcp_billing_export_resource_v1_*`. Enable **Detailed usage cost** in the Billing console (no Terraform toggle). Query with `jobs.query`. | BigQuery dataset IAM | Day (resource-level rows) | `billing_account_id`, `invoice.month`, `cost`, `currency`, `cost_type`, `usage_start_time`, `usage.amount`, `project.id`, `service.id`, `sku.id`, `resource.name`, `labels`, `credits` (net = `cost` + sum of `credits.amount`) |
| [Datadog](datadog/) | `GET https://api.{site}/api/v2/usage/estimated_cost`, `/historical_cost`, `/hourly_usage` | Headers `DD-API-KEY` + `DD-APPLICATION-KEY` (`usage_read` + `billing_read`) | Day (cost); hour (usage) | `attributes.org_name`, `account_name`, `date`, `charges[].charge_type`, `charges[].cost`, `charges[].product_name`. Skip `charge_type=total` when summing. Estimated is in-month cumulative |
| [Aiven](aiven/) | `GET https://api.aiven.io/v1/organization/{id}/invoices` and `…/invoices/{number}/csv` | `Authorization: Bearer {token}` (`organization:billing:read`) | Invoice period; CSV lines | JSON: `invoice_number`, `state`, `currency`, `total_usd`, `period_begin`. CSV: `project_name`, `service_name`, `service_type`, `plan`, `cloud`, `quantity`, `total_usd`, `tags` |
| [Confluent Cloud](confluent/) | `GET https://api.confluent.cloud/billing/v1/costs` (`end_date` exclusive; paginate `page_token`) | Basic auth `api_key`:`api_secret` (`BillingAdmin`) | Day | `start_date`, `granularity`, `product`, `line_type`, `amount`, `price`, `quantity`, `unit`, `discount_amount`, `resource.id` |
| [ClickHouse Cloud](clickhouse/) | `GET https://api.clickhouse.cloud/v1/organizations/{id}/usageCost` (max 31 days). Join `GET …/services` | Basic auth `key_id`:`key_secret` (`view-billing`) | Day | `date`, `locked`, `totalCHC`, `entityId`, `entityName`, `entityType`, `metrics.computeCHC` / `storageCHC` / `dataTransferCHC` — amounts are **CHC**, not USD |
| [Scaleway](scaleway/) | `GET https://api.scaleway.com/billing/v2beta1/consumptions?organization_id=&billing_period=` | `X-Auth-Token: {secret_key}` (`BillingReadOnly`) | Month | `billing_period`, `product_name`, `sku`, `category_name`, `project_id`, `billed_quantity`, `value.units` + `value.nanos` (EUR) |
| [Elastic Cloud](elastic-cloud/) | `GET https://cloud.elastic.co/api/v2/billing/organizations/{id}/costs/instances?from=&to=&include_names=true` (RFC 3339; chunk 1 UTC day) | `Authorization: ApiKey {key}` (Billing admin) | Day | `instances[].id`, `name`, `type`, `total_ecu`, `product_line_items[].sku`, `quantity.value`, `rate.value` — ECU; USD ≈ `quantity × rate` |
| [Cloudflare PayGo](cloudflare/) | `GET https://api.cloudflare.com/client/v4/accounts/{id}/billing-usage` (+ `/billing-usage/info`). Window must include the billing-cycle anchor; max ~31 days | `Authorization: Bearer {token}` (Account Billing Read) | Charge period (often day) | `BilledCost`, `BillingCurrency`, `ChargePeriodStart`, `ChargeDescription`, `ServiceName`, `ConsumedQuantity`, `ZoneId`, `SubscriptionId` |
| [Snowflake](snowflake/) | SQL, not HTTP. `SNOWFLAKE.ORGANIZATION_USAGE.USAGE_IN_CURRENCY_DAILY` (+ `WAREHOUSE_METERING_HISTORY`, `ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY`) | Key-pair JWT, role `ORGANIZATION_BILLING_VIEWER` | Day (`$`); warehouse hour; query | `USAGE_DATE`, `USAGE_IN_CURRENCY`, `CURRENCY`, `SERVICE_TYPE`, `BILLING_TYPE`, `ACCOUNT_LOCATOR`, `IS_ADJUSTMENT`. Metering: `CREDITS_USED_COMPUTE`. Queries: `CREDITS_ATTRIBUTED_COMPUTE` |
| [Anthropic Console](anthropic/#claude-console--admin-cost-report) | `GET https://api.anthropic.com/v1/organizations/cost_report` (+ `/usage_report/messages`, `/users`, `/api_keys`). `limit` = day buckets, max 31 | `x-api-key` Admin key + `anthropic-version: 2023-06-01` | Day | Cost: `amount` (USD cents as string), `cost_type`, `token_type`, `model`, `workspace_id`. Allocate `$` via Messages `account_id` / `api_key_id` — Cost Report has no user dimension |
| [Anthropic Claude Enterprise](anthropic/#claude-enterprise-analytics-claudeai) | `GET https://api.anthropic.com/v1/organizations/analytics/user_cost_report` (max 31 days; data from 2026-01-01) | `x-api-key` Analytics key (`read:analytics`). Not the Console Admin key | Day, per user | Per-user billed `$` (or usage credits on seat plans). Do not sum with org-wide `/analytics/cost_report` (double-counts / no user) |
| [OpenAI](openai/) | `GET https://api.openai.com/v1/organization/costs` (`group_by` `project_id` then `line_item`+`api_key_id`; `limit` = 1–180 day buckets). Catalog: `/organization/projects`, `…/api_keys` | `Authorization: Bearer {sk-admin-…}` | Day | `results[].amount.value`, `amount.currency`, `line_item`, `quantity`, `project_id`, `api_key_id`. Names from the Admin catalog (key **owner**, not request user) |
| [Cursor](cursor/) | `POST https://api.cursor.com/teams/filtered-usage-events` (`startDate`/`endDate` epoch ms; `page`/`pageSize` max 1000). Not `/teams/daily-usage-data` | Basic auth, username = Admin API key, empty password | Hour (event-level) | `usageEvents[].timestamp`, `userEmail`, `model`, `kind`, `isChargeable`, `chargedCents`, `tokenUsage.inputTokens` / `outputTokens` / `totalCents`. Sum `chargedCents` on chargeable events |

## Why these settings

Cloud bills are only useful for FinOps if the export is complete:

- **AWS** — CUR 2.0 (not CUR 1.0), hourly, resource IDs, [EKS/ECS split cost allocation](aws/#kubernetes-split-cost-allocation), [IAM principal for Bedrock](aws/#bedrock-cost-allocation-line_item_iam_principal), full column list, Parquet overwrite. Optional [FOCUS 1.2](aws/#optional-focus-12) sits next to CUR, it does not replace it. See the [options timeline](aws/#timeline--options-to-turn-on).
- **Azure** — both Actual Cost and Amortized Cost ([FOCUS does not amortize correctly yet](#why-not-focus-only)), daily MonthToDate because [Azure restates the month](azure/#why-daily-monthtodate-azure-restates-the-month), partitioned Parquet, backfill via `exports/run`. Official `azurerm` resources cannot do this; the [azapi path](azure/#why-azapi-instead-of-the-official-azurerm-resources) can. This example is [subscription-scoped](azure/#export-scope-parent_id); you can point `parent_id` at the billing account / enrollment for the whole invoice, but unused RI/SP rows then often have empty `ResourceId`. Do not use a management group (usage only, no amortized).
- **GCP** — Detailed usage cost (resource-level), not the standard summary table. [There is no Terraform resource for the export toggle](gcp/#why-there-is-no-terraform-resource-for-the-export-toggle). Enable GKE cost allocation on clusters if you need pod-level rows.
- **SaaS / smaller clouds** — a dedicated principal with billing-read only, never an admin user token.
- **LLM platforms** — Admin / Analytics keys (not inference keys). Anthropic Console Cost Report is billed `$` (allocate users via Messages usage). Claude Enterprise Analytics is a **separate** `user_cost_report` key (`read:analytics`) with per-user `$` (usage credits on seat-based plans). OpenAI Costs is billed `$` per project × line item × API key. Cursor `filtered-usage-events` is event-level `chargedCents`.

## Why not FOCUS-only

FOCUS is a useful **schema**, not a complete FinOps feed on every cloud:

| Cloud | Native export (this repo’s default) | FOCUS in this repo |
| --- | --- | --- |
| AWS | CUR 2.0 hourly Parquet (split cost, IAM principal, full columns) | Optional `FOCUS_1_2_AWS` in the same bucket (`enable_focus=true`) |
| Azure | Actual + Amortized daily Parquet | Optional `FocusCost` 1.2-preview (`enable_focus=true`). Do not drop Actual + Amortized — FOCUS does not amortize correctly yet |
| GCP | Detailed usage cost in **your** dataset | Console-only Google-managed FOCUS dataset. Not created here |

Add FOCUS when you want the standard columns. Keep the native export as the source of truth until FOCUS matches invoice + amortization + allocation flags.

## How to use

```bash
cd aws   # or azure, gcp, datadog, aiven, confluent, clickhouse, scaleway, cloudflare, snowflake
terraform init
terraform apply
```

Anthropic, OpenAI, Cursor, and Elastic Cloud: create the Admin / Analytics / Organization API key in the vendor console. There is nothing to apply on the vendor side. Claude Console and Claude Enterprise Analytics need **two** keys.

Provider credentials stay in environment variables or `terraform.tfvars` (not committed). See each folder README for the exact variables.

## Optional FinOps tool registration

Each `main.tf` has commented `costory_*` blocks. Leave them commented unless you use [Costory](https://docs.costory.io/setup/billing). The stacks are the provider-side export (or credentials) only.

## Related docs

- [AWS Data Exports](https://docs.aws.amazon.com/cur/latest/userguide/what-is-data-exports.html)
- [FOCUS 1.2 with AWS columns](https://docs.aws.amazon.com/cur/latest/userguide/table-dictionary-focus-1-2-aws.html)
- [Azure Cost Management exports](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-improved-exports)
- [Azure FOCUS cost and usage schema](https://learn.microsoft.com/en-us/azure/cost-management-billing/dataset-schema/cost-usage-details-focus)
- [Azure Cost Management scopes](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/understand-work-scopes)
- [Set up Cloud Billing export to BigQuery](https://cloud.google.com/billing/docs/how-to/export-data-bigquery-setup)
- [Datadog Usage Metering API](https://docs.datadoghq.com/api/latest/usage-metering/)
- [Aiven organization permissions](https://aiven.io/docs/platform/concepts/permissions)
- [Confluent Cloud Costs API](https://docs.confluent.io/cloud/current/billing/ccloud-cost-api.html)
- [ClickHouse Cloud usageCost API](https://clickhouse.com/docs/products/cloud/api-reference/billing/get-organization-usage-costs)
- [Scaleway Consumption API](https://www.scaleway.com/en/developers/api/billing/consumption)
- [Elastic Cloud instances costs](https://www.elastic.co/docs/api/doc/cloud-billing/operation/operation-getcostsbyinstancesv2)
- [Cloudflare PayGo usage](https://developers.cloudflare.com/api/resources/billing/subresources/usage/methods/paygo/)
- [Snowflake USAGE_IN_CURRENCY_DAILY](https://docs.snowflake.com/en/sql-reference/organization-usage/usage_in_currency_daily)
- [Anthropic Usage and Cost Admin API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)
- [Anthropic Analytics API](https://platform.claude.com/docs/en/manage-claude/analytics-api)
- [OpenAI Organization Costs](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs)
- [Cursor Admin API](https://cursor.com/docs/account/teams/admin-api)
