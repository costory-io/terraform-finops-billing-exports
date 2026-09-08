# Datadog billing export with Terraform

Terraform for **Datadog usage and billing API** access. Datadog does not drop files into object storage. The export is a least-privilege service account plus keys that can call the [Usage Metering API](https://docs.datadoghq.com/api/latest/usage-metering/).

## What this stack creates

1. Custom role with only `usage_read` and `billing_read`.
2. Service account that holds that role.
3. Org API key (`DD-API-KEY`).
4. Scoped service-account application key (`DD-APPLICATION-KEY`).

Both scopes are required. `usage_read` alone returns volumes (hosts, log GB) but not cost. Marketplace-billed orgs sometimes get `403` on billing endpoints even with `billing_read` — that is a Datadog-side limitation.

## Prerequisites

- Terraform >= 1.5
- Datadog provider >= 3.52 (application-key `scopes`)
- An existing API key + application key for Terraform (`org_app_keys_write` and role management)
- A unique email that is not already a user in the org

## Apply

```bash
cd datadog
terraform init
terraform apply \
  -var="datadog_api_key=$DD_API_KEY" \
  -var="datadog_app_key=$DD_APP_KEY" \
  -var='service_account_email=billing-export@example.com'
```

For EU, set `datadog_api_url = "https://api.datadoghq.eu"` (also `us3.datadoghq.com`, `us5.datadoghq.com`).

## Outputs

- `api_key` — org API key
- `application_key` — scoped application key
- `service_account_id`, `role_id`

Store both keys in a secret manager. The application key value cannot be imported later.

## Billing API

Base: `https://api.{site}/api/v2` (US1 `api.datadoghq.com`, EU `api.datadoghq.eu`). Headers: `DD-API-KEY`, `DD-APPLICATION-KEY`.

| Endpoint | Use |
| --- | --- |
| [`GET /usage/estimated_cost`](https://docs.datadoghq.com/api/latest/usage-metering/#get-estimated-cost-across-your-account) | In-month estimated cost (`view=sub-org`, `cost_aggregation=cumulative`) |
| [`GET /usage/historical_cost`](https://docs.datadoghq.com/api/latest/usage-metering/#get-historical-cost-across-your-account) | Finalized months (`start_month` / `end_month`) |
| [`GET /usage/hourly_usage`](https://docs.datadoghq.com/api/latest/usage-metering/#get-hourly-usage-by-product-family) | Hourly usage (`filter[product_families]=all`) |

```bash
curl -sS "https://api.datadoghq.com/api/v2/usage/estimated_cost?view=sub-org&cost_aggregation=cumulative&start_date=2026-01-01&end_date=2026-01-31&include_connected_accounts=true" \
  -H "DD-API-KEY: $DD_API_KEY" \
  -H "DD-APPLICATION-KEY: $DD_APPLICATION_KEY"
```

Estimated cost covers the open month (plus a short grace window). Historical cost is the closed-month invoice view. Usage is volumes (hosts, log GB), not dollars.

## Data output

Each cost response is a JSON:API `data[]` array. Charge lines live under `attributes.charges`:

```json
{
  "data": [
    {
      "attributes": {
        "org_name": "acme",
        "account_name": "prod",
        "date": "2026-01-15T00:00:00+00:00",
        "charges": [
          {
            "charge_type": "usage",
            "cost": 12.34,
            "product_name": "infra_hosts",
            "last_aggregation_function": "sum"
          }
        ]
      }
    }
  ]
}
```

Hourly usage rows use `attributes.timestamp`, `attributes.product_family`, `attributes.account_name`, and `attributes.measurements[]` (`usage_type`, `value`).

| Field | Type | Notes |
| --- | --- | --- |
| `attributes.org_name` | string | Parent org |
| `attributes.account_name` | string | Sub-org / account |
| `attributes.date` | timestamp | Day (cost APIs) |
| `charges[].charge_type` | string | Skip `"total"` when summing products |
| `charges[].cost` | number | USD; estimated is **cumulative** in-month |
| `charges[].product_name` | string | Product family |

## Official docs

- [datadog_application_key / scopes](https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/application_key)
- [datadog_service_account_application_key](https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/service_account_application_key)
- [Usage Metering API](https://docs.datadoghq.com/api/latest/usage-metering/)
- [Billing and usage permissions](https://docs.datadoghq.com/account_management/rbac/permissions/#billing-and-usage)
