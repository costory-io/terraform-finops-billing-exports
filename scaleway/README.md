# Scaleway billing export with Terraform

Terraform for **Scaleway consumption API** access (`GET /billing/v2beta1/consumptions`). Scaleway does not write billing files to Object Storage for this flow. The export is an IAM application with `BillingReadOnly` and an API key.

## What this stack creates

1. IAM application (`billing-export` by default).
2. Organization-scoped policy with `BillingReadOnly` (not project-scoped).
3. API key on that application.

The consumption API authenticates with `X-Auth-Token` = **secret key**. The access key is unused for billing.

## Prerequisites

- Terraform >= 1.5
- Scaleway credentials that can manage IAM applications, policies, and API keys
- Organization ID (Organization dashboard, not a project ID)

## Apply

```bash
cd scaleway
terraform init
terraform apply \
  -var='scaleway_access_key=...' \
  -var='scaleway_secret_key=...' \
  -var='organization_id=...' \
  -var='project_id=...'
```

`SCW_ACCESS_KEY`, `SCW_SECRET_KEY`, `SCW_DEFAULT_ORGANIZATION_ID`, and `SCW_DEFAULT_PROJECT_ID` also work.

## Outputs

- `organization_id`
- `application_id`
- `access_key` — optional
- `secret_key` — send as `X-Auth-Token`

The secret is shown once. An imported `scaleway_iam_api_key` has a null secret.

## Billing API

[`GET https://api.scaleway.com/billing/v2beta1/consumptions`](https://www.scaleway.com/en/developers/api/billing/consumption) — header `X-Auth-Token: {secret_key}`. Organization-scoped; pass `organization_id`. Paginate (`page` / `page_size`). The feed is **month-grained** and live for the open month.

```bash
curl -sS "https://api.scaleway.com/billing/v2beta1/consumptions?organization_id=$SCW_DEFAULT_ORGANIZATION_ID&billing_period=2026-01" \
  -H "X-Auth-Token: $SCW_SECRET_KEY"
```

## Data output

Each consumption line (money is `google.type.Money`: `units` + `nanos` / 1e9):

| Field | Type | Notes |
| --- | --- | --- |
| `billing_period` | string | `YYYY-MM` |
| `currency_code` | string | Usually `EUR` |
| `value.units`, `value.nanos` | int | Invoice amount |
| `product_name`, `resource_name`, `sku` | string | Product / SKU |
| `category_name` | string | e.g. Object Storage |
| `project_id`, `project_name` | string | Project |
| `unit`, `billed_quantity` | string / number | Usage |
| `consumer_id` | string | Organization or consumer |
| `organization_name` | string | Org display name |
| `total_discount_untaxed_value` | number | Discount |
| `updated_at` | timestamp | Last API update |

```json
{
  "billing_period": "2026-01",
  "product_name": "Standard One Zone",
  "sku": "/storage/obj/usage-onezone_ia/fr-par",
  "category_name": "Object Storage",
  "project_id": "proj-1",
  "unit": "gigabyte_hour",
  "billed_quantity": 466,
  "value": { "currency_code": "EUR", "units": "0", "nanos": 920000000 }
}
```

## Official docs

- [Scaleway Consumption API](https://www.scaleway.com/en/developers/api/billing/consumption)
- [IAM permission sets](https://www.scaleway.com/en/docs/iam/reference-content/permission-sets/)
- [scaleway_iam_application](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/iam_application)
- [scaleway_iam_policy](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/iam_policy)
- [scaleway_iam_api_key](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/iam_api_key)
