# Azure Cost Management billing export with Terraform

Terraform for **Azure Cost Management exports**: a storage account, a container, and two daily Parquet exports (Actual Cost and Amortized Cost). An optional FOCUS 1.2-preview export and a backfill of up to 12 past months sit next to those, they do not replace them.

Azure has no first-class `azurerm` resource for the current Cost Management export API, so the stack uses [`azapi`](https://registry.terraform.io/providers/Azure/azapi/latest/docs) against `Microsoft.CostManagement/exports@2025-03-01`.

## What this stack creates

1. Resource group + Standard LRS storage account + `billing-exports` container.
2. Daily **ActualCost** export under `actuals/{exportName}/`.
3. Daily **AmortizedCost** export under `amortized/{exportName}/`.
4. Optional daily **FocusCost** 1.2-preview under `focus/{exportName}/` (`enable_focus=true`).
5. Read/list SAS (900 days by default) so a FinOps tool can pull the blobs.
6. Optional `exports/run` actions for historical months.

## Why azapi instead of the official `azurerm` resources

We tried three shapes:

| Approach | What you get | What you lose |
| --- | --- | --- |
| `azurerm` Cost Management export resources | Storage + a legacy export | Not the latest export API. No Parquet / partitioned improved exports. **You cannot trigger a backfill** (`exports/run`) from Terraform. |
| `azurerm` for storage, then backfill in the portal | Familiar provider for the bucket | Manual, easy to miss months, not reviewable in git. |
| **`azapi` on `Microsoft.CostManagement/exports@2025-03-01`** (this repo) | Every option the API exposes: Actual + Amortized, Parquet, `partitionData`, daily schedule, `exports/run` backfill | You write the ARM body instead of a typed resource. |

The last one is the only way to get a complete, repeatable FinOps export from Terraform.

## Why Actual + Amortized, not FOCUS

| Export | What it is |
| --- | --- |
| Actual Cost | Cash / invoice view |
| Amortized Cost | Reservations and savings plans spread across the term |

Both are required. Actual alone hides commitment economics; Amortized alone does not match the invoice.

**FOCUS (`FocusCost`) does not correctly output amortized costs yet.** Until it does, a FOCUS-only export is not a substitute for the two native datasets. This stack can add FOCUS as a **third** export (`enable_focus=true`) for the schema — do not drop Actual + Amortized for it.

```bash
terraform apply -var='subscription_id=...' -var='enable_focus=true'
```

`dataVersion` is `1.2-preview`. Files land under `focus/{exportName}/` with partitioned Parquet and overwrite.

## Why daily MonthToDate (Azure restates the month)

Azure can **modify the current month’s bill until the month closes**: reservations, savings plans, credits, marketplace, and corrections land throughout the period. A one-shot export on day 1 is wrong by day 30.

- `timeframe = MonthToDate` rebuilds the in-progress month on every run.
- `recurrence = Daily` is how you pick up those restatements.
- `time_static` pins `schedule.from` so later applies do not rewrite the start date and force a replace.

Scheduled exports only write **going forward**. History is a separate `exports/run` (below).

## Why `partitionData = true`

Partitioned Parquet is the better layout for FinOps tools: smaller files, parallel reads, a manifest next to the data. With partitioning, blobs land under `{rootFolderPath}/{exportName}/` — that is why outputs are `actuals_path` and `amortized_path`, not the container root.

## Why a SAS (and why 900 days)

A container-scoped **read + list** SAS over HTTPS is the easiest way to hand a FinOps tool the blobs. 900 days avoids rotating a token every quarter for a feed that should just keep working.

A **cleaner** production setup is federated identity (workload identity / Entra ID on the reader, no long-lived token). Use that when the consuming tool supports it. SAS is the lowest-friction default for copy-paste.

`time_static` pins the SAS start so Terraform does not mint a new token on every plan.

## Export scope (`parent_id`)

The export is attached to one Azure **scope**. That scope is what appears in the Parquet files. You *can* hang it on a parent billing account; Microsoft documents that Actual and Amortized both work there. Completeness is not the same at every parent.

This example uses the subscription you pass in:

```hcl
parent_id = "/subscriptions/${var.subscription_id}"
```

`subscription_id` is also passed to the `azurerm` provider (where the storage account lives). Same ID, two jobs. Storage can stay in this subscription even if you move the export to a billing scope.

| Scope | `parent_id` | What you get | What you lose |
| --- | --- | --- | --- |
| Subscription (this example) | `/subscriptions/{id}` | Usage for that sub, dense `ResourceId` / tags | Other subscriptions; org-level purchases not allocated here |
| EA enrollment / MCA billing account | `/providers/Microsoft.Billing/billingAccounts/{id}` | The **invoice**: usage + Marketplace + reservation / savings-plan purchases. Actual + Amortized both supported. | Some rows have **empty `SubscriptionId` / `ResourceId`** (unused reservations, unused savings plans, rounding). Resource-level allocation is thinner even though the money is more complete. |
| MCA billing profile / invoice section | `.../billingProfiles/{id}` or `.../invoiceSections/{id}` | Same datasets, narrower invoice slice | Same empty-ID rows for unallocated commitment waste |
| EA department or enrollment account | `.../departments/{id}` or `.../enrollmentAccounts/{id}` | Usage | **Purchases are missing** (Marketplace, reservations). Less complete than the enrollment. |
| Management group | `/providers/Microsoft.Management/managementGroups/{id}` | Usage only, CSV, no compression. EA only. | **No purchases, no amortized, no FOCUS.** Do not use this as the FinOps feed. |

For a whole-org bill, point `parent_id` at the **billing account / enrollment**, not a management group. Microsoft’s own exports FAQ: missing subscription IDs are left null on unused reservations, unused savings plans, and rounding — that is why a parent-account file can look “less complete” at resource grain.

See [Understand and work with scopes](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/understand-work-scopes) and [Create and manage exports](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-improved-exports).

## Prerequisites

- Terraform >= 1.5
- Azure credentials that can create resource groups, storage, and Cost Management exports on the target scope

## Apply

```bash
cd azure
terraform init
terraform apply -var='subscription_id=00000000-0000-0000-0000-000000000000'
```

Then backfill history as a second apply:

```bash
terraform apply \
  -var='subscription_id=00000000-0000-0000-0000-000000000000' \
  -var='run_backfill=true'
```

**After the backfill succeeds, turn it off.** `azapi_resource_action` with `when = "apply"` fires on every apply while the actions stay in the config. Either:

1. Set `run_backfill=false` (or drop the `-var`) and apply again, or
2. Comment out the two `azapi_resource_action` "backfill_*" blocks in [`main.tf`](main.tf).

Leaving them enabled re-exports the same months on the next apply.

| Variable | Default | Description |
| --- | --- | --- |
| `subscription_id` | *(required)* | Subscription for the `azurerm` provider and, in this example, the export scope |
| `location` | `West Europe` | Region for RG + storage |
| `resource_group_name` | `billing-cost-exports` | Resource group name |
| `sas_token_validity_days` | `900` | SAS lifetime |
| `backfill_month_count` | `12` | Months to export when backfill runs |
| `run_backfill` | `false` | Trigger `exports/run` |
| `enable_focus` | `false` | Also create FOCUS 1.2-preview (keep Actual + Amortized) |

## Outputs

- `storage_account_name`, `storage_container_name`
- `actuals_path`, `amortized_path`
- `focus_path` — set when `enable_focus=true`
- `blob_endpoint_with_sas` (sensitive)

## Billing API

Azure is also a **push export**. Cost Management writes Parquet to the storage account; you then read the blobs.

| Step | API | What it does |
| --- | --- | --- |
| Create the export | [`PUT {scope}/providers/Microsoft.CostManagement/exports/{name}?api-version=2025-03-01`](https://learn.microsoft.com/en-us/rest/api/cost-management/exports/create-or-update) | Daily Actual + Amortized Parquet (optional third: `FocusCost`) |
| Backfill a month | [`POST …/exports/{name}/run`](https://learn.microsoft.com/en-us/rest/api/cost-management/exports/run) | Historical `MonthToDate` |
| Read the files | Blob `List` + `Get` under `actuals/{exportName}/` and `amortized/{exportName}/` | Partitioned Parquet + manifest |

`{scope}` is `parent_id` in this stack (subscription by default).

## Data output

Two datasets, same schema (column names are case-insensitive in Parquet / BigQuery often lowercases them):

| Column | Type | Notes |
| --- | --- | --- |
| `BillingAccountId` | string | Billing account |
| `BillingPeriodStartDate`, `BillingPeriodEndDate` | timestamp | Invoice month |
| `UsageDateTime` / `Date` | timestamp | Charge day |
| `ChargeType` | string | Usage, Purchase, Tax, … |
| `MeterName`, `MeterCategory`, `MeterSubCategory`, `ServiceFamily` | string | Meter hierarchy |
| `CostInUsd`, `PreTaxCost`, `CostInBillingCurrency`, `PayGCostInUsd` | double | Cost measures |
| `Currency` / `BillingCurrency` | string | Invoice currency |
| `Quantity` / `UsageQuantity`, `UnitOfMeasure` | double / string | Usage |
| `ResourceId` / `InstanceId`, `ResourceGroupName`, `ResourceLocation` | string | Resource |
| `ConsumedService`, `ProductName`, `ServiceName` | string | Product |
| `SubscriptionId`, `SubscriptionName` | string | Subscription |
| `Tags`, `AdditionalInfo` | string (JSON) | Labels / extras |
| `BenefitId` | string | Reservation / savings plan |
| `InvoiceSectionName`, `CostCenter` | string | Cost center |

Actual Cost is cash/invoice. Amortized Cost spreads reservations and savings plans. You need both.

## Official docs

- [Create and manage Cost Management exports](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-improved-exports)
- [Understand and work with scopes](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/understand-work-scopes)
- [Cost Management exports REST API](https://learn.microsoft.com/en-us/rest/api/cost-management/exports)
- [azapi_resource](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/azapi_resource)
- [FOCUS cost and usage details schema](https://learn.microsoft.com/en-us/azure/cost-management-billing/dataset-schema/cost-usage-details-focus)
