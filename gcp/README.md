# GCP BigQuery billing export with Terraform

Terraform for the **GCP Cloud Billing → BigQuery** destination: a US or EU dataset (and optional reader IAM). **There is no Terraform resource that enables the billing export itself.** After apply, turn on **Detailed usage cost** in the Billing console and point it at this dataset.

Use Detailed usage cost as the FinOps feed. The standard usage cost table is a summary.

## What this stack creates

1. BigQuery dataset `{dataset_id}` in `US` or `EU` (required for detailed export).
2. Optional Data Viewer + Metadata Viewer on `reader_members`.

Google creates the table after you enable the export:

`{project}.{dataset}.gcp_billing_export_resource_v1_{BILLING_ACCOUNT_ID}`

Hyphens in the billing account ID become underscores.

## Why there is no Terraform resource for the export toggle

Cloud Billing export to BigQuery is configured on the **billing account**, and Google has not published an API (or a `google_*` resource) that links a dataset to that export. HashiCorp’s Google provider tracks this as a long-standing gap.

| Step | Terraform? | Where |
| --- | --- | --- |
| Create the destination dataset | Yes (`google_bigquery_dataset`) | This stack |
| Grant readers on the dataset | Yes (`google_bigquery_dataset_iam_member`) | This stack |
| Enable Detailed / Standard / Pricing / FOCUS export | **No** | Billing console → **Billing export** |
| GKE cost allocation (pod-level rows) | On the **cluster**, not here | `cost_management_config { enabled = true }` on `google_container_cluster` |

The honest copy-paste is: apply this dataset, then click the toggle. Do not pretend a `null_resource` + `gcloud` is a supported API.

## Why Detailed usage cost, not Standard

| Export | Table | What you get | What you lose |
| --- | --- | --- | --- |
| **Detailed usage cost** (this repo) | `gcp_billing_export_resource_v1_*` | Resource IDs, labels, SKU-level cost | Slightly larger table |
| Standard usage cost | `gcp_billing_export_v1_*` | Project / SKU totals | No resource grain |
| Pricing | `cloud_pricing_export` | List prices | Needs BigQuery Data Transfer API; not the bill |
| FOCUS (preview) | Google-managed `gcp_billing_export_focus_*` | FOCUS schema | Immutable dataset you do not create here. Enable separately in the console |

Backfill is **current month + previous month** only. Older history is not available from this export.

## GKE cost allocation

Detailed (and FOCUS) exports include GCE resource IDs automatically. **Pod-level GKE rows need cost allocation enabled on the cluster.** That is a cluster setting, not a billing-export setting. Enable it when you create or update the cluster; it is not retroactive.

## Prerequisites

- Terraform >= 1.5
- Credentials that can create a BigQuery dataset on `project_id`
- Billing Admin (or equivalent) on the billing account, to click the export toggle after apply
- Dataset location `US` or `EU`

## Apply

```bash
cd gcp
terraform init
terraform apply \
  -var='project_id=my-billing-project' \
  -var='billing_account_id=XXXXXX-XXXXXX-XXXXXX'
```

Then in [Billing export](https://console.cloud.google.com/billing):

1. Open the billing account → **Billing export** → **BigQuery export**.
2. Under **Detailed usage cost**, Edit settings.
3. Project = `project_id`, dataset = `billing_export` (or your `dataset_id`).
4. Wait a few hours. The detailed table appears with the ID printed in `expected_detailed_table_id`.

Optional variables:

| Variable | Default | Description |
| --- | --- | --- |
| `project_id` | *(required)* | Project that hosts the dataset |
| `billing_account_id` | *(required)* | Used to print the expected table name |
| `dataset_id` | `billing_export` | Dataset ID |
| `location` | `EU` | Must be `US` or `EU` |
| `reader_members` | `[]` | `user:` / `group:` / `serviceAccount:` readers |

## Outputs

- `dataset_id`, `dataset_location`
- `expected_detailed_table_id` — table Google creates after the toggle
- `expected_standard_table_id` — only if you also enable Standard
- `console_billing_export_url` — console page for the toggle

## Billing API

GCP billing for FinOps is a **push export** into BigQuery, not a pull billing API.

| Step | API | What it does |
| --- | --- | --- |
| Create the dataset | BigQuery `datasets.insert` (`google_bigquery_dataset`) | Empty destination |
| Enable the export | **None** (console) | Starts writing `gcp_billing_export_resource_v1_*` |
| Read the bill | BigQuery `jobs.query` / `tabledata.list` on that table | Daily resource-level rows |

There is no Cloud Billing REST method that returns the same line items.

## Data output

Detailed usage cost (nested structs; column names are lowercased in some tools):

| Field | Type | Notes |
| --- | --- | --- |
| `billing_account_id` | string | Billing account |
| `invoice.month` | string | `YYYYMM` |
| `cost` | float | Billable cost |
| `currency` | string | Invoice currency |
| `cost_type` | string | regular, tax, adjustment, rounding |
| `usage_start_time`, `usage_end_time` | timestamp | Usage window |
| `usage.amount`, `usage.unit` | float / string | Quantity |
| `project.id`, `project.name`, `project.labels` | mixed | Project |
| `service.id`, `service.description` | string | Service |
| `sku.id`, `sku.description` | string | SKU |
| `location.location`, `location.region`, `location.country` | string | Region |
| `resource.name`, `resource.global_name` | string | Resource (detailed only) |
| `labels`, `system_labels`, `project.labels` | array of structs | Key/value |
| `credits` | array&lt;struct&gt; | Promos, CUD, SUD, … |

Credits are nested; net cost is `cost` plus the sum of `credits.amount` (credits are negative).

## Official docs

- [Set up Cloud Billing data export to BigQuery](https://cloud.google.com/billing/docs/how-to/export-data-bigquery-setup)
- [Understand the Cloud Billing data tables](https://cloud.google.com/billing/docs/how-to/export-data-bigquery-tables)
- [FOCUS export to BigQuery](https://cloud.google.com/billing/docs/how-to/export-data-bigquery-tables#focus)
- [GKE cost allocation](https://cloud.google.com/kubernetes-engine/docs/how-to/cost-allocation)
- [google_bigquery_dataset](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/bigquery_dataset)
