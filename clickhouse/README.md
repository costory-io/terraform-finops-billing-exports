# ClickHouse Cloud billing export with Terraform

Terraform for **ClickHouse Cloud** usage and billing access. The official provider can manage [custom roles](https://registry.terraform.io/providers/ClickHouse/clickhouse/latest/docs/resources/role) but **cannot create organization API keys** yet ([issue #585](https://github.com/ClickHouse/terraform-provider-clickhouse/issues/585)). This stack creates a least-privilege role; you create the key in the console (or via OpenAPI) and attach it.

## What this stack creates

1. Looks up the built-in **Billing** system role (usage + invoices; also payment methods).
2. Creates a custom role `billing-export-reader` with only:
   - `control-plane:organization:view`
   - `control-plane:organization:view-billing`
3. Optionally assigns an existing API key ID to that custom role.

Avoid `control-plane:organization:manage-billing` unless the key must change payment methods.

## Create the API key

In the [ClickHouse Cloud console](https://clickhouse.cloud/) → API keys, create a key and assign `billing-export-reader` (or the built-in Billing role).

Or call OpenAPI with an admin key:

```bash
curl -sS -X POST \
  -u "$CLICKHOUSE_CLOUD_API_KEY:$CLICKHOUSE_CLOUD_API_SECRET" \
  "https://api.clickhouse.cloud/v1/organizations/$CLICKHOUSE_ORG_ID/keys" \
  -H 'Content-Type: application/json' \
  -d '{"name":"billing-export","assignedRoleIds":["<billing-export-role-id>"],"state":"enabled"}'
```

Then pass `billing_api_key_id` into Terraform if you want the assignment in state.

This covers **ClickHouse Cloud** only, not self-managed ClickHouse.

## Prerequisites

- Terraform >= 1.5
- ClickHouse Cloud admin API key (used only by Terraform)
- Organization ID

## Apply

```bash
cd clickhouse
terraform init
terraform apply \
  -var='organization_id=...' \
  -var='admin_token_key=...' \
  -var='admin_token_secret=...'
```

## Outputs

- `organization_id`
- `billing_export_role_id` — assign this to the export key
- `system_billing_role_id` — built-in Billing role (broader)

## Billing API

Base: `https://api.clickhouse.cloud/v1`. Basic auth (`key_id`:`key_secret`). Max window on usage cost is **31 days**.

| Endpoint | Use |
| --- | --- |
| [`GET /organizations/{orgId}/usageCost?from_date=&to_date=`](https://clickhouse.com/docs/products/cloud/api-reference/billing/get-organization-usage-costs) | Daily per-entity cost in ClickHouse Credits (CHC) |
| [`GET /organizations/{orgId}/services`](https://clickhouse.com/docs/cloud/manage/openapi) | Service catalog (name, region, tags) to join onto cost lines |

```bash
curl -sS -u "$CLICKHOUSE_CLOUD_API_KEY:$CLICKHOUSE_CLOUD_API_SECRET" \
  "https://api.clickhouse.cloud/v1/organizations/$CLICKHOUSE_ORG_ID/usageCost?from_date=2026-01-01&to_date=2026-01-31"
```

## Data output

`usageCost` returns `result.costs[]`. Amounts are **ClickHouse Credits**, not USD.

| Field | Type | Notes |
| --- | --- | --- |
| `date` | string (date) | UTC day |
| `locked` | bool | Month closed |
| `totalCHC` | number | Total credits that day / entity |
| `entityId`, `entityName`, `entityType` | string | Service / warehouse / … |
| `serviceId`, `dataWarehouseId` | string | Join to `/services` |
| `metrics` | object | `computeCHC`, `storageCHC`, `backupCHC`, `dataTransferCHC`, `initialLoadCHC`, `publicDataTransferCHC`, `interRegionTier1DataTransferCHC`, `interRegionTier2DataTransferCHC`, … |

`/services` rows: `id`, `name`, `provider`, `region`, `state`, `dataWarehouseId`, `tags`.

```json
{
  "date": "2026-01-15",
  "locked": false,
  "entityId": "svc-1",
  "entityName": "analytics",
  "entityType": "service",
  "serviceId": "svc-1",
  "totalCHC": 12.5,
  "metrics": { "computeCHC": 10.0, "storageCHC": 2.5 }
}
```

## Official docs

- [Console roles and permissions](https://clickhouse.com/docs/cloud/reference/security/console-roles)
- [ClickHouse Cloud OpenAPI](https://clickhouse.com/docs/cloud/manage/openapi)
- [Get organization usage costs](https://clickhouse.com/docs/products/cloud/api-reference/billing/get-organization-usage-costs)
- [clickhouse_role](https://registry.terraform.io/providers/ClickHouse/clickhouse/latest/docs/resources/role)
- [clickhouse_role_assignment](https://registry.terraform.io/providers/ClickHouse/clickhouse/latest/docs/resources/role_assignment)
