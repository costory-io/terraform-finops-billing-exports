# Terraform FinOps billing exports: AWS CUR 2.0, Azure, GCP, Datadog, SaaS

Copy-paste Terraform to set up **billing exports** for FinOps: AWS CUR 2.0 (BCM Data Exports, hourly Parquet), Azure Cost Management (Actual + Amortized, optional FOCUS), GCP BigQuery detailed usage cost, Datadog, Aiven, Confluent Cloud, ClickHouse Cloud, Scaleway, Elastic Cloud, Cloudflare, Snowflake, Anthropic (Console Admin + Claude Enterprise Analytics), OpenAI, and Cursor.

Each folder is a standalone stack: one `README.md` and one `main.tf`. Cloud and most SaaS examples create the provider-side export or the least-privilege credentials a FinOps tool needs. Anthropic, OpenAI, Cursor, and Elastic Cloud have no provider Terraform for minting Admin / Analytics / Organization keys — those READMEs document the console key, the billing API, and the response schema.

Each README also documents:

- **Billing API** — the endpoint(s) that return usage / cost
- **Data output** — the fields (and types) those endpoints return

## Providers

| Provider | What Terraform creates | Billing API | Folder |
| --- | --- | --- | --- |
| [AWS CUR 2.0](aws/) | S3 bucket + BCM Data Exports (hourly Parquet, split cost allocation, Bedrock IAM principal). Optional FOCUS 1.2 in the same bucket | Push to S3 (BCM Data Exports), not a pull API | [aws/](aws/) |
| [Azure Cost Management](azure/) | Storage + daily Actual and Amortized Parquet via azapi + SAS + optional backfill. Optional FOCUS 1.2-preview. Subscription-scoped by default; billing account is optional | `Microsoft.CostManagement/exports` then blobs | [azure/](azure/) |
| [GCP BigQuery billing](gcp/) | BigQuery dataset (US/EU) + optional reader IAM. **The export toggle has no API** — enable Detailed usage cost in the Billing console | Push to BigQuery (`gcp_billing_export_resource_v1_*`) | [gcp/](gcp/) |
| [Datadog billing API](datadog/) | Service account, `usage_read` + `billing_read` role, scoped keys | `GET /api/v2/usage/{estimated_cost,historical_cost,hourly_usage}` | [datadog/](datadog/) |
| [Aiven Billing API](aiven/) | Application user, `organization:billing:read`, API token | `GET /v1/organization/{id}/invoices` + invoice CSV | [aiven/](aiven/) |
| [Confluent Cloud costs](confluent/) | Service account, `BillingAdmin`, Cloud API key | `GET /billing/v1/costs` | [confluent/](confluent/) |
| [ClickHouse Cloud usage](clickhouse/) | Custom role with `view-billing` (assign an API key in the console) | `GET /v1/organizations/{id}/usageCost` | [clickhouse/](clickhouse/) |
| [Scaleway consumption](scaleway/) | IAM application, `BillingReadOnly`, API key | `GET /billing/v2beta1/consumptions` | [scaleway/](scaleway/) |
| [Elastic Cloud instance costs](elastic-cloud/) | Console Organization API key only (`Billing admin`) | `GET /api/v2/billing/organizations/{id}/costs/instances` | [elastic-cloud/](elastic-cloud/) |
| [Cloudflare PayGo usage](cloudflare/) | API token, Account `Billing Read` | `GET /accounts/{id}/billing-usage` (+ `/info`) | [cloudflare/](cloudflare/) |
| [Snowflake Organization Usage](snowflake/) | Service user, key pair, `ORGANIZATION_BILLING_VIEWER` + query viewer roles | SQL: `USAGE_IN_CURRENCY_DAILY` (+ warehouse metering, query attribution) | [snowflake/](snowflake/) |
| [Anthropic Admin Cost Report](anthropic/#claude-console--admin-cost-report) | Console Admin API key only | `GET /v1/organizations/cost_report` (+ Messages usage + user/key catalog) | [anthropic/](anthropic/) |
| [Anthropic Claude Enterprise Analytics](anthropic/#claude-enterprise-analytics-claudeai) | claude.ai Analytics API key only (`read:analytics`, primary owner) | `GET /v1/organizations/analytics/user_cost_report` | [anthropic/](anthropic/) |
| [OpenAI Admin Costs](openai/) | Console Admin API key only | `GET /v1/organization/costs` (+ project / API-key catalog) | [openai/](openai/) |
| [Cursor Admin usage](cursor/) | Console Admin API key only | `POST /teams/filtered-usage-events` | [cursor/](cursor/) |

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
