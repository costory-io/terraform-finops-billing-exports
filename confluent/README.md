# Confluent Cloud billing export with Terraform

Terraform for **Confluent Cloud costs API** access (`GET /billing/v1/costs`). Confluent Cloud does not export invoice files to object storage. The export is a service account with `BillingAdmin` and a Cloud API key.

## What this stack creates

1. Service account (`billing-export` by default).
2. `BillingAdmin` role binding on the organization CRN.
3. Cloud API key owned by that service account (`prevent_destroy = true`).

`BillingAdmin` is the least-privilege predefined role that can call the Costs API. There is no read-only billing role. Do not put a trailing slash on the organization CRN.

## Prerequisites

- Terraform >= 1.5
- Cloud API key of an OrganizationAdmin (or equivalent) for Terraform
- Environment variables `CONFLUENT_CLOUD_API_KEY` / `CONFLUENT_CLOUD_API_SECRET` also work

## Apply

```bash
cd confluent
terraform init
terraform apply \
  -var='confluent_cloud_api_key=...' \
  -var='confluent_cloud_api_secret=...'
```

This covers **Confluent Cloud** only, not self-managed Confluent Platform.

## Outputs

- `organization_id`
- `service_account_id`
- `api_key`, `api_secret` (secret is sensitive)

## Billing API

[`GET https://api.confluent.cloud/billing/v1/costs`](https://docs.confluent.io/cloud/current/billing/ccloud-cost-api.html) — Basic auth (`api_key` / `api_secret`).

`end_date` is **exclusive**. A December window `2025-12-01` … `2025-12-31` must send `end_date=2026-01-01`. Paginate with `page_token` from `metadata.next`.

```bash
curl -sS -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" \
  "https://api.confluent.cloud/billing/v1/costs?start_date=2026-01-01&end_date=2026-02-01"
```

## Data output

Each `data[]` item:

| Field | Type | Notes |
| --- | --- | --- |
| `start_date`, `end_date` | string (date) | Inclusive start, exclusive end |
| `granularity` | string | Usually daily |
| `product` | string | Kafka, Connect, ksqlDB, … |
| `line_type` | string | Charge class |
| `network_access_type` | string | Public / private / … |
| `amount` | number | Billed amount |
| `price` | number | Unit price |
| `quantity` | number | Usage |
| `unit` | string | Pricing unit |
| `discount_amount` | number | Discount |
| `original_amount` | number | Pre-discount |
| `resource` | object | Nested resource id / display name / environment |

```json
{
  "start_date": "2026-01-15",
  "end_date": "2026-01-16",
  "granularity": "DAILY",
  "product": "KAFKA",
  "line_type": "KAFKA_NUM_CKUS",
  "amount": 1.23,
  "price": 0.30,
  "quantity": 4.1,
  "unit": "CKU-hours",
  "resource": { "id": "lkc-abc", "display_name": "prod-cluster" }
}
```

## Official docs

- [Confluent Cloud Costs API](https://docs.confluent.io/cloud/current/billing/ccloud-cost-api.html)
- [BillingAdmin role](https://docs.confluent.io/cloud/current/security/access-control/rbac/predefined-rbac-roles.html#billingadmin)
- [confluent_service_account](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_service_account)
- [confluent_api_key](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_api_key)
- [confluent_role_binding](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_role_binding)
