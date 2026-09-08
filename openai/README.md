# OpenAI billing export

OpenAI does not write invoice files to object storage. The export is an **Admin API key** (`sk-admin-…`) created at [platform.openai.com/settings/organization/admin-keys](https://platform.openai.com/settings/organization/admin-keys). A project inference key cannot call the Costs API.

The official [`openai/openai`](https://registry.terraform.io/providers/openai/openai/latest/docs) Terraform provider manages projects, users, and spend *alerts*. It does **not** create Admin keys or export cost line items.

## Create the Admin API key

1. Organization **Admin keys** → new key.
2. Recommended scopes: read-only **usage** (`api.usage.read`) plus organization / API-key / project read.
3. Store it in a secret manager. It is shown once.

## Billing API

Base: `https://api.openai.com/v1`. Header: `Authorization: Bearer {admin_key}`.

Costs `group_by` is only `project_id` / `line_item` / `api_key_id`. Grouping all three org-wide can explode `results[]`, so pull in two steps: `group_by=project_id`, then one call per project with `line_item` + `api_key_id`. `limit` is **day buckets** (1–180).

The Costs API returns `api_key_id`, not the key name, and does not group by request user. Names come from the Admin catalog (key **owner**, not the request actor).

| Endpoint | Use |
| --- | --- |
| [`GET /organization/costs`](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs) | Billed `$` |
| [`GET /organization/projects`](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/projects) | `project_id` → name |
| [`GET /organization/projects/{project_id}/api_keys`](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/projects) | `api_key_id` → name / owner |

```bash
curl -sS "https://api.openai.com/v1/organization/costs?start_time=1767225600&limit=31&group_by[]=project_id" \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY"
```

`start_time` / `end_time` are Unix seconds. Usage endpoints (`/organization/usage/completions`, …) are token series, not billed dollars.

## Data output

Each Costs page has `data[]` time buckets. A bucket:

| Field | Type | Notes |
| --- | --- | --- |
| `start_time`, `end_time` | int (unix) | Bucket bounds |
| `results[].amount.value` | number | Billed amount |
| `results[].amount.currency` | string | Usually `usd` |
| `results[].line_item` | string | e.g. `gpt-4o, input_tokens` |
| `results[].quantity`, `results[].quantity_unit` | number / string | Tokens, requests, … |
| `results[].project_id` | string | Present when grouped |
| `results[].api_key_id` | string | Present when grouped |

After stamping catalog names, a flattened FinOps row looks like:

| Field | Type | Notes |
| --- | --- | --- |
| `charge_date` | string | UTC day from `start_time` |
| `amount_value`, `amount_currency` | number / string | Billed `$` |
| `line_item`, `quantity`, `quantity_unit` | string / number | SKU / usage |
| `project_id`, `project_name` | string | Project |
| `api_key_id`, `api_key_name` | string | Key |
| `user_id`, `user_name`, `user_email` | string | Key **owner** |
| `owner_type` | string | `user` / `service_account` |

```json
{
  "start_time": 1767225600,
  "end_time": 1767312000,
  "results": [
    {
      "amount": { "value": 1.25, "currency": "usd" },
      "line_item": "gpt-4o, input_tokens",
      "quantity": 1000,
      "quantity_unit": "tokens",
      "project_id": "proj_abc",
      "api_key_id": "key_abc"
    }
  ]
}
```

This is **API Platform** spend. ChatGPT Enterprise / Codex analytics are separate products.

## Optional: register the key in a FinOps tool

There is nothing to apply on the OpenAI side. Store the Admin key in a secret manager and point your FinOps tool at it.

A commented Costory resource sits at the bottom of [`main.tf`](main.tf) if your provider version includes `costory_billing_datasource_openai`.

## Official docs

- [Organization Costs](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs)
- [Admin API keys](https://platform.openai.com/settings/organization/admin-keys)
- [Admin APIs](https://developers.openai.com/api/docs/guides/admin-apis)
