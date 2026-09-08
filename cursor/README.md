# Cursor billing export

Cursor does not write invoice files to object storage. The export is an **Admin API key** (`crsr_…`) created at [cursor.com/dashboard](https://cursor.com/dashboard) → **API Keys**. Required scope: `admin:*`. There is no Terraform resource that mints that key.

## Create the Admin API key

1. Team admin → dashboard → **API Keys** → **New API Key**.
2. Copy the key immediately. It is shown once.

## Billing API

[`POST https://api.cursor.com/teams/filtered-usage-events`](https://cursor.com/docs/account/teams/admin-api) — Basic auth, username = API key, empty password.

`startDate` / `endDate` are **epoch milliseconds**. Data is aggregated hourly; poll at most once per hour (60 req/min on this path). Paginate with `page` / `pageSize` (max 1000).

To reconcile with team spend totals, sum `chargedCents` on chargeable events.

```bash
curl -sS -X POST https://api.cursor.com/teams/filtered-usage-events \
  -u "$CURSOR_ADMIN_API_KEY:" \
  -H "Content-Type: application/json" \
  -d '{
    "startDate": 1767225600000,
    "endDate": 1767312000000,
    "page": 1,
    "pageSize": 1000
  }'
```

Optional body filters: `email`, `userId`, `serviceAccountId`, `cloudAgentId`, `automationId`, `hostingType`. Combined with `AND`.

`POST /teams/daily-usage-data` is an aggregate metrics feed, not the line-item cost export.

## Data output

Envelope:

| Field | Type | Notes |
| --- | --- | --- |
| `totalUsageEventsCount` | number | Total matching events |
| `pagination.currentPage`, `hasNextPage`, `pageSize`, `numPages` | mixed | Paging |
| `period.startDate`, `period.endDate` | number | Window (ms) |
| `usageEvents[]` | array | Events |

Each `usageEvents[]` item:

| Field | Type | Notes |
| --- | --- | --- |
| `timestamp` | string | Epoch ms |
| `userEmail` | string | Requesting user |
| `serviceAccountId`, `serviceAccountName` | string | Service-account events only |
| `model` | string | Model id |
| `kind` | string | e.g. `Usage-based`, `Included in Business` |
| `maxMode`, `isTokenBasedCall`, `isChargeable`, `isHeadless` | bool | Billing flags |
| `requestsCosts` | number | Request units |
| `chargedCents` | number | Amount charged (model + Cursor Token Rate when applicable) |
| `cursorTokenFee` | number | Token-rate cents when present |
| `tokenUsage.inputTokens`, `outputTokens`, `cacheWriteTokens`, `cacheReadTokens` | number | Tokens |
| `tokenUsage.totalCents` | number | Model cost in cents |
| `tokenUsage.discountPercentOff` | number | Discount % |
| `conversationId`, `cloudAgentId`, `automationId` | string | Session / agent joins |

```json
{
  "totalUsageEventsCount": 113,
  "pagination": { "currentPage": 1, "hasNextPage": true, "pageSize": 1000 },
  "usageEvents": [
    {
      "timestamp": "1750979225854",
      "userEmail": "developer@company.com",
      "model": "claude-4.5-sonnet",
      "kind": "Usage-based",
      "isChargeable": true,
      "isTokenBasedCall": true,
      "chargedCents": 21.36,
      "tokenUsage": {
        "inputTokens": 126,
        "outputTokens": 450,
        "totalCents": 20.18
      }
    }
  ]
}
```

Filter FinOps totals to `isChargeable = true`. `chargedCents / 100` is USD.

## Optional: register the key in a FinOps tool

There is no Terraform resource that mints the Admin API key. After you create it in the console, store it in a secret manager and point your FinOps tool at it.

A commented `costory_billing_datasource_cursor` block sits at the bottom of [`main.tf`](main.tf) if you use Costory.

## Official docs

- [Admin API — filtered usage events](https://cursor.com/docs/account/teams/admin-api)
- [Cursor APIs / creating keys](https://cursor.com/docs/api)
