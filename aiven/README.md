# Aiven billing export with Terraform

Terraform for **Aiven Billing API** access. Aiven does not write invoice files to object storage. The export is a dedicated [application user](https://aiven.io/docs/platform/concepts/application-users) with `organization:billing:read` and an API token.

## What this stack creates

1. Organization application user (`billing-export` by default).
2. Application-user token (`full_token`).
3. A commented `aiven_organization_permission` block for `organization:billing:read` — merge it into the resource that already owns org permissions, or grant the same permission in the Aiven console.

## Important: permission resource ownership

`aiven_organization_permission` **replaces** every principal on that organization / resource pair. If you already manage org permissions in Terraform, **do not apply this resource as-is**. Copy the `permissions { ... }` block into your existing resource.

If permissions are still console-managed, import first, then add the billing-export user next to the existing principals:

```bash
terraform import aiven_organization_permission.billing_export \
  ORGANIZATION_ID/organization/ORGANIZATION_ID
```

## Prerequisites

- Terraform >= 1.5
- An Aiven token with organization-admin rights (used only by Terraform)
- Organization ID (`org1…`)

## Apply

```bash
cd aiven
terraform init
terraform apply \
  -var='aiven_api_token=...' \
  -var='organization_id=org1...'
```

## Outputs

- `organization_id`
- `application_user_id`
- `api_token` (sensitive) — send this to the Billing API

## Billing API

Base: `https://api.aiven.io/v1`. Header: `Authorization: Bearer {token}`.

| Endpoint | Use |
| --- | --- |
| [`GET /organization/{org_id}/invoices`](https://api.aiven.io/doc/) | Invoice list (period, totals, currency) |
| [`GET /organization/{org_id}/invoices/{invoice_number}/csv`](https://api.aiven.io/doc/) | Invoice lines as CSV |

```bash
curl -sS "https://api.aiven.io/v1/organization/$ORG_ID/invoices" \
  -H "Authorization: Bearer $AIVEN_TOKEN"

curl -sS "https://api.aiven.io/v1/organization/$ORG_ID/invoices/$INVOICE_NUMBER/csv" \
  -H "Authorization: Bearer $AIVEN_TOKEN" \
  -H "Accept: text/csv"
```

The CSV is the line-item feed. The JSON list is metadata so you know which invoices to download.

## Data output

**Invoices** (JSON):

| Field | Type | Notes |
| --- | --- | --- |
| `invoice_number`, `invoice_id` | string | Invoice identity |
| `state` | string | e.g. generated / paid |
| `currency` | string | Invoice currency |
| `total_usd` | string | Total in USD |
| `period_begin`, `period_end` | string | Billing period |
| `generated_at` | string | Invoice timestamp |
| `organization_id`, `billing_group_id` | string | Scope |

**Invoice lines** (CSV columns):

| Field | Type | Notes |
| --- | --- | --- |
| `begin_time`, `end_time` | timestamp | Line period |
| `project_name`, `service_name`, `service_type` | string | Resource |
| `plan`, `cloud`, `description` | string | SKU / region / text |
| `quantity`, `unit`, `unit_price_local` | number / string | Usage |
| `total`, `total_usd` | number | Line cost |
| `line_currency` | string | Local currency |
| `commitment_name` | string | Commitment if any |
| `tags` | string | Project / service tags |
| `invoice_number`, `organization_id` | string | Join keys |

## Official docs

- [aiven_organization_application_user](https://registry.terraform.io/providers/aiven/aiven/latest/docs/resources/organization_application_user)
- [aiven_organization_application_user_token](https://registry.terraform.io/providers/aiven/aiven/latest/docs/resources/organization_application_user_token)
- [aiven_organization_permission](https://registry.terraform.io/providers/aiven/aiven/latest/docs/resources/organization_permission)
- [Organization roles and permissions](https://aiven.io/docs/platform/concepts/permissions)
- [Aiven API — invoices](https://api.aiven.io/doc/)
