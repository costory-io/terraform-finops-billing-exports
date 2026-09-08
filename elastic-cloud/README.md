# Elastic Cloud billing export

Elastic Cloud does not write invoice files to object storage. The export is an **Organization API key** with billing access plus the organization ID. There is no Terraform resource that mints that key.

## Create the Organization API key

1. In the [Elastic Cloud console](https://cloud.elastic.co/) → organization **API keys**, create a key with the **Billing admin** role (billing API access).
2. Copy the organization ID (organization settings) and the key. The key is shown once.

A user API key that is not organization-scoped, or a key without billing, returns empty instances or `403`.

## Prerequisites

- Terraform >= 1.5
- Organization ID
- Organization API key with billing access (created in the console)

There is nothing to apply on the Elastic side. [`main.tf`](main.tf) only holds the optional Costory registration.

## Billing API

[`GET https://cloud.elastic.co/api/v2/billing/organizations/{organization_id}/costs/instances`](https://www.elastic.co/docs/api/doc/cloud-billing/operation/operation-getcostsbyinstancesv2)

Header: `Authorization: ApiKey {key}`. `from` / `to` are RFC 3339. Pass `include_names=true` so instance names are populated. The feed is **day-grained**; chunk longer windows one UTC day at a time.

```bash
curl -sS "https://cloud.elastic.co/api/v2/billing/organizations/$ELASTIC_ORG_ID/costs/instances?\
from=2026-01-15T00:00:00Z&\
to=2026-01-16T00:00:00Z&\
include_names=true" \
  -H "Authorization: ApiKey $EC_API_KEY" \
  -H "Accept: application/json"
```

Related endpoints (not required for the instance feed): [`/costs/items`](https://www.elastic.co/docs/api/doc/cloud-billing/group/endpoint-billing-costs-analysis) (org-wide line items), `/costs/instances/{id}/items`.

Amounts on instances are **Elastic Consumption Units (ECU)**. USD on a product line is `quantity.value * rate.value`.

## Data output

Envelope: `instances[]` plus `total_ecu` for the window.

Each instance:

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | Deployment / serverless project / other billed instance |
| `name` | string | Present when `include_names=true` |
| `type` | string | e.g. `deployment`, `elasticsearch`, `observability`, `security` |
| `total_ecu` | number | ECU for that instance in the window |
| `product_line_items[]` | array | SKU lines |

Each `product_line_items[]` item:

| Field | Type | Notes |
| --- | --- | --- |
| `name` | string | Product display name |
| `type` | string | Line class |
| `sku` | string | SKU (often includes cloud `_aws-` / `_gcp-` / `_azure-`) |
| `unit` | string | Usage unit |
| `total_ecu` | number | Line ECU |
| `quantity.value` | number | Usage |
| `rate.value` | number | Unit price (USD) |
| `rate.formatted_value` | string | Display rate |

```json
{
  "instances": [
    {
      "id": "dep-1",
      "name": "prod-logs",
      "type": "deployment",
      "total_ecu": 12,
      "product_line_items": [
        {
          "name": "Elasticsearch",
          "type": "capacity",
          "sku": "elasticsearch.storage_aws-eu-west-1",
          "unit": "GB-hour",
          "total_ecu": 12,
          "quantity": { "value": 24 },
          "rate": { "value": 0.032, "formatted_value": "$0.032" }
        }
      ]
    }
  ]
}
```

A flattened FinOps row is one product line per instance per day: `cost_usd = quantity.value * rate.value`, `resource_id = instance.id`.

## Optional: register the key in a FinOps tool

Store the Organization API key in a secret manager and point your FinOps tool at it.

A commented `costory_billing_datasource_elastic_cloud` block sits at the bottom of [`main.tf`](main.tf) if you use Costory.

## Official docs

- [Get instances costs](https://www.elastic.co/docs/api/doc/cloud-billing/operation/operation-getcostsbyinstancesv2)
- [Billing Costs Analysis](https://www.elastic.co/docs/api/doc/cloud-billing/group/endpoint-billing-costs-analysis)
- [Elastic Cloud API keys](https://www.elastic.co/docs/deploy-manage/api-keys/elastic-cloud-api-keys)
- [Authentication](https://www.elastic.co/docs/api/doc/cloud-billing/authentication)
