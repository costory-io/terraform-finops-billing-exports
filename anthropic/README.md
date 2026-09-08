# Anthropic billing export

Anthropic does not write invoice files to object storage. There are **two**
FinOps feeds, with **different keys that are not interchangeable**:

| Product | Key | Created in | Who | Billing API |
| --- | --- | --- | --- | --- |
| Claude Console (API platform / Claude Code) | Admin API key (`sk-ant-admin-…`) | [Claude Console → Admin keys](https://platform.claude.com/settings/admin-keys) | Org admin | [`GET /v1/organizations/cost_report`](#billing-api-console) |
| Claude Enterprise (claude.ai) | Analytics API key (`read:analytics`) | claude.ai → Organization settings → API | **Primary owner** | [`GET /v1/organizations/analytics/user_cost_report`](#billing-api-enterprise) |

There is no Terraform resource that mints either key.

---

## Claude Console — Admin Cost Report

This is the **Claude Console Admin API** (API platform / Claude Code billed `$`).

### Create the Admin API key

1. In the Claude Console → **Admin keys**, create a key with cost and usage read.
2. Store it in a secret manager. It is shown once.

Only organization admins can create Admin API keys. A normal inference key (`sk-ant-…`) cannot call these endpoints. An Analytics key cannot call them either.

### Billing API (Console)

Base: `https://api.anthropic.com/v1/organizations`. Headers: `x-api-key: {admin_key}`, `anthropic-version: 2023-06-01`.

Cost Report is billed **USD**. It has no user dimension. Messages usage + the user/key catalog are how you allocate `$` to an actor.

| Endpoint | Use |
| --- | --- |
| [`GET /cost_report`](https://platform.claude.com/docs/en/api/admin/cost_report/retrieve) | Billed `$` (`group_by[]=workspace_id` + `group_by[]=description`) |
| [`GET /usage_report/messages`](https://platform.claude.com/docs/en/api/admin/usage_report/retrieve_messages) | Token (and web-search) counts per user / API key |
| [`GET /users`](https://platform.claude.com/docs/en/api/admin/users) | `account_id` → name / email |
| [`GET /api_keys`](https://platform.claude.com/docs/en/api/admin/api_keys) | Key → owner |
| [`GET /workspaces`](https://platform.claude.com/docs/en/api/admin/workspaces) | Workspace names |

`limit` on Cost Report / Messages is **day buckets** (max 31). Chunk longer windows. `group_by` on Messages is capped at 5.

```bash
curl -sS "https://api.anthropic.com/v1/organizations/cost_report?\
starting_at=2026-01-01T00:00:00Z&\
ending_at=2026-02-01T00:00:00Z&\
group_by[]=workspace_id&\
group_by[]=description" \
  -H "x-api-key: $ANTHROPIC_ADMIN_KEY" \
  -H "anthropic-version: 2023-06-01"
```

Priority Tier `$` is **not** on Cost Report. Do not use `/usage_report/claude_code` for billed dollars (client-side estimates).

### Data output (Console)

Cost Report buckets (`data[]`) contain `starting_at` / `ending_at` and `results[]`. Amounts are USD **cents as a decimal string**.

| Field | Type | Notes |
| --- | --- | --- |
| `amount` | string | Cents, e.g. `"123.4"` = $1.23 |
| `currency` | string | Always `USD` |
| `cost_type` | string | `tokens`, `web_search`, `code_execution`, `session_usage` |
| `token_type` | string | `uncached_input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation.ephemeral_5m_input_tokens`, `cache_creation.ephemeral_1h_input_tokens` |
| `model`, `context_window`, `service_tier`, `inference_geo` | string | Present when grouping by `description` |
| `workspace_id`, `description` | string | Workspace / line text |

Messages usage adds `account_id`, `api_key_id`, and token counts. After joining users/keys, a flattened FinOps row looks like:

| Field | Type | Notes |
| --- | --- | --- |
| `charge_date` | string | UTC day |
| `cost_usd` | number | Allocated billed dollars |
| `actor_email`, `actor_name`, `account_id` | string | User (or unattributed remainder) |
| `api_key_id`, `api_key_name` | string | Key traffic |
| `workspace_id`, `workspace_name` | string | Workspace |
| `model`, `token_type`, `token_count` | string / number | Usage share used for allocation |
| `resource_type` | string | `user` / `api_key` / `unattributed` |

---

## Claude Enterprise Analytics (claude.ai)

This is **claude.ai Enterprise** seat / usage-credit spend (chat, Cowork, Claude Code on the Enterprise org, Slack, Chrome, …). It is **not** the Console Admin Cost Report above.

On **usage-based** Enterprise plans the cost endpoints are billed `$`. On **seat-based** plans they reflect **usage credits only**, not the seat SKU list price.

### Create the Analytics API key

1. Sign in as the **primary owner**.
2. claude.ai → **Organization settings → API** → enable public API access.
3. Create a key with scope `read:analytics`. Store it in a secret manager. It is shown once.

An Admin API key (`sk-ant-admin-…`) cannot call these endpoints.

### Billing API (Enterprise)

Base: `https://api.anthropic.com/v1`. Headers: `x-api-key: {analytics_key}`, `anthropic-version: 2023-06-01`.

Use **per-user** cost so billed `$` does not double-count. Org-wide [`/analytics/cost_report`](https://platform.claude.com/docs/en/api/http/admin/analytics/cost/list) has no user and includes API-key / automation traffic — pull it later as a remainder, not in the same total.

| Endpoint | Use |
| --- | --- |
| [`GET /organizations/analytics/user_cost_report`](https://platform.claude.com/docs/en/api/http/admin/analytics/cost/list_by_user) | Per-user billed `$` (or usage credits) |

List params use **bracket notation**. Do not change filters mid-pagination (400). A cursor can expire after a refresh → **HTTP 410**; restart that window from the first page.

Hard API constraints:

| Constraint | Value |
| --- | --- |
| Earliest data | `2026-01-01T00:00:00Z` |
| Lookback | `starting_at` within the last **365 days** |
| Max range per request | **31 days** (`ending_at` exclusive) |
| `1d` page `limit` | 1–1000 rows (default 20). `cost_type` / `token_type` fan-out does **not** count toward `limit` |
| Rate limit | **60 req/min per org** (not per key) |
| Amounts | Decimal **strings in cents**. `"41280.000000"` → **$412.80**. Divide by 100 |
| Freshness | Typically within 4h, up to 24h. A date can restate for **~30 days** |

Always set `ending_at` (do not omit). When omitted, the response includes a tail after `data_refreshed_at` that is incomplete.

Do **not** `group_by[]=rbac_group_id` for billed `$`: a user in several groups contributes **full** spend to each named group, so the sum can exceed the org total.

```bash
curl -sS "https://api.anthropic.com/v1/organizations/analytics/user_cost_report?\
starting_at=2026-01-01T00:00:00Z&\
ending_at=2026-02-01T00:00:00Z&\
bucket_width=1d&\
group_by[]=product&\
group_by[]=model&\
group_by[]=cost_type&\
group_by[]=token_type&\
limit=1000" \
  -H "x-api-key: $ANTHROPIC_ANALYTICS_KEY" \
  -H "anthropic-version: 2023-06-01"
```

Engagement endpoints (user activity, DAU/WAU/MAU, projects, skills, connectors) are **not** billed `$`.

### Data output (Enterprise)

Envelope: `data[]`, `data_refreshed_at`, `has_more`, `next_page`, `organization_id`. Land **one row per `data[]` item**. Grain: user × day × product × model × cost_type × token_type.

| Field | Type | Notes |
| --- | --- | --- |
| `charge_date` | string | UTC day from row `starting_at` (`bucket_width=1d`) |
| `starting_at`, `ending_at` | string | RFC 3339 bucket bounds (`ending_at` exclusive) |
| `organization_id` | string | Org id on the response |
| `account_name` | string | Display label you store next to the key (not sent to Anthropic) |
| `user_id`, `user_email`, `user_name`, `user_deleted` | string / bool | Flattened from `actor` |
| `amount_cents` | string | Post-discount, pre-credit, **cents** |
| `list_amount_cents` | string | List price, **cents** |
| `currency` | string | Always `USD` today |
| `product` | string | `chat`, `claude_code`, `cowork`, `office_agent`, `claude_in_chrome`, `claude_design`, `claude-tag`, `other`, … |
| `model` | string | e.g. `claude-opus-5` |
| `cost_type` | string | `tokens`, `web_search`, `code_execution` |
| `token_type` | string | Same token types as Cost Report |
| `requests` | number | Not attributable once you group by `cost_type` / `token_type` (null) |
| `data_refreshed_at` | string | Export watermark |

```json
{
  "data": [
    {
      "actor": {
        "type": "user_actor",
        "user_id": "user_01AbCdEfGhIjKlMnOpQrSt",
        "email": "jane@example.com",
        "name": "Jane Smith",
        "deleted": false
      },
      "amount": "41280.000000",
      "list_amount": "51600.000000",
      "currency": "USD",
      "product": "chat",
      "model": "claude-opus-5",
      "cost_type": "tokens",
      "token_type": "uncached_input_tokens",
      "starting_at": "2026-01-15T00:00:00Z",
      "ending_at": "2026-01-16T00:00:00Z"
    }
  ],
  "data_refreshed_at": "2026-01-15T12:00:00Z",
  "has_more": false,
  "organization_id": "org_013FP9SaFPBg7Kw7fetjn6cF"
}
```

Flattened FinOps row: `cost_usd = amount_cents / 100`, `resource_type = user`, `resource_name = "Name (email)"`. Token counts are **not** on this cost endpoint.

If your organization uses Claude Code through Amazon Bedrock, this API does not return that Claude Code activity.

## Optional: register the key in a FinOps tool

There is no Terraform resource that mints either key. After you create it in the console, store it in a secret manager and point your FinOps tool at it.

Commented Costory blocks sit at the bottom of [`main.tf`](main.tf) if you use Costory. Console Admin is `costory_billing_datasource_anthropic`. Claude Enterprise Analytics is a **separate** datasource (type `ANTHROPIC_CLAUDE_AI`); connect it in the Costory UI if your provider version has no resource yet.

## Official docs

- [Usage and Cost Admin API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api) (Console)
- [Get Cost Report](https://platform.claude.com/docs/en/api/admin/cost_report/retrieve)
- [Get Messages usage report](https://platform.claude.com/docs/en/api/admin/usage_report/retrieve_messages)
- [Admin API keys](https://platform.claude.com/settings/admin-keys)
- [Analytics API overview](https://platform.claude.com/docs/en/manage-claude/analytics-api) (which key)
- [Get Per-User Cost](https://platform.claude.com/docs/en/api/http/admin/analytics/cost/list_by_user)
