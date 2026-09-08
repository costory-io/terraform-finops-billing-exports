# Cloudflare billing export with Terraform

Terraform for **Cloudflare PayGo billing usage** (`GET /accounts/{account_id}/billing-usage`). Cloudflare does not write invoice files to object storage for this flow. The export is an API token with **Account → Billing → Read**.

This is the **self-serve / PayGo** usage API. If `GET …/billing-usage/info` returns `covered: false`, the account is on an enterprise contract and this public API will not return billed `$`. Enterprise needs Cloudflare to enable the restricted v2 usage API.

## What this stack creates

1. Looks up the account-scoped **Billing Read** permission group.
2. Creates an API token scoped to one account with that permission only.

The Terraform principal needs a token that can create API tokens (`API Tokens Write`).

## Prerequisites

- Terraform >= 1.5
- Cloudflare API token that can mint tokens (`CLOUDFLARE_API_TOKEN`)
- Account ID

## Apply

```bash
cd cloudflare
terraform init
terraform apply \
  -var='cloudflare_api_token=...' \
  -var='account_id=...'
```

`CLOUDFLARE_API_TOKEN` also works for the provider if you omit the variable.

## Outputs

- `account_id`
- `api_token` (sensitive) — send as `Authorization: Bearer`
- `api_token_id`

The token value is shown once.

## Billing API

Base: `https://api.cloudflare.com/client/v4`. Header: `Authorization: Bearer {token}`.

| Endpoint | Use |
| --- | --- |
| [`GET /accounts/{account_id}/billing-usage/info`](https://developers.cloudflare.com/api/resources/billing/subresources/usage/methods/paygo/) | `covered` + subscription `billing_cycle_anchor_timestamp` |
| [`GET /accounts/{account_id}/billing-usage`](https://developers.cloudflare.com/api/resources/billing/subresources/usage/methods/paygo/) | PayGo usage rows (`from` / `to`) |

`from` / `to` are ISO-8601 dates. The range **must include the subscription billing-cycle anchor day**, or Cloudflare returns an empty `result`. Practical max span is **31 days**. Align windows to the cycle from `/info`.

```bash
curl -sS "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/billing-usage/info" \
  -H "Authorization: Bearer $CF_API_TOKEN"

curl -sS "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/billing-usage?from=2026-01-01&to=2026-01-31" \
  -H "Authorization: Bearer $CF_API_TOKEN"
```

Official docs also publish these as `/accounts/{id}/paygo-usage` and `/paygo-usage-info` (same PayGo feed). Restricted v2 is [`GET /accounts/{id}/billable/usage`](https://developers.cloudflare.com/api/resources/billing/subresources/usage/methods/get) (FOCUS-shaped; cost fields may still be empty).

## Data output

Standard Cloudflare envelope `{ success, errors, result }`. `result` on usage is an **array of rows** (PascalCase FOCUS-ish fields). No pagination on PayGo v1.

| Field | Type | Notes |
| --- | --- | --- |
| `BilledCost` | number | Charge after discounts |
| `EffectiveCost`, `ContractedCost`, `ListCost` | number | Cost variants |
| `BillingCurrency` | string | ISO 4217 |
| `BillingAccountId`, `BillingAccountName` | string | Account |
| `BillingPeriodStart` | string | Cycle start |
| `ChargePeriodStart`, `ChargePeriodEnd` | string | Usage window |
| `ChargeCategory`, `ChargeClass`, `ChargeDescription` | string | Line class / text |
| `ConsumedQuantity`, `ConsumedUnit` | number / string | Usage |
| `PricingQuantity`, `PricingUnit` | number / string | Priced quantity |
| `ServiceName`, `ServiceFamilyName`, `ServiceProviderName` | string | Product |
| `SubscriptionId` | string | Subscription |
| `ZoneId`, `ZoneName` | string | Zone when applicable |
| `InvoiceIssuerName`, `HostProviderName` | string | Issuer / host |

```json
{
  "success": true,
  "result": [
    {
      "BilledCost": 12.34,
      "BillingCurrency": "USD",
      "BillingAccountId": "a1b2c3",
      "ChargePeriodStart": "2026-01-01",
      "ChargePeriodEnd": "2026-01-02",
      "ChargeDescription": "Workers Paid",
      "ServiceName": "Workers",
      "ConsumedQuantity": 1.5,
      "ConsumedUnit": "million requests",
      "ZoneId": "zone-1",
      "ZoneName": "example.com",
      "SubscriptionId": "sub-1"
    }
  ]
}
```

## Official docs

- [Get Account Usage (PayGo)](https://developers.cloudflare.com/api/resources/billing/subresources/usage/methods/paygo/)
- [API token permissions — Billing Read](https://developers.cloudflare.com/fundamentals/api/reference/permissions/)
- [cloudflare_api_token](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/api_token)
