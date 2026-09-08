# Snowflake billing export with Terraform

Terraform for a **read-only Snowflake service user** that can query organization billed `$` and per-query credits. Snowflake does not push a FinOps file export. The feed is SQL against the shared `SNOWFLAKE` database.

Invoice `$` is [`ORGANIZATION_USAGE.USAGE_IN_CURRENCY_DAILY`](https://docs.snowflake.com/en/sql-reference/organization-usage/usage_in_currency_daily) (account × day × SKU). Warehouse hours and query splits come from other views so you can allocate that `$` — they are not a second invoice.

## What this stack creates

1. Account role `BILLING_EXPORT` (name configurable).
2. Service user with an RSA key pair (`tls_private_key`, PKCS#8).
3. Grants:
   - `SNOWFLAKE.ORGANIZATION_BILLING_VIEWER` — `USAGE_IN_CURRENCY_DAILY`
   - `SNOWFLAKE.ORGANIZATION_USAGE_VIEWER` — `WAREHOUSE_METERING_HISTORY`
   - `SNOWFLAKE.USAGE_VIEWER` + `SNOWFLAKE.GOVERNANCE_VIEWER` — `ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY` and `QUERY_HISTORY`
   - `USAGE` on an existing warehouse (queries need a warehouse)
4. Role granted to the service user; default role / warehouse set on the user.

Apply this from an **ORGADMIN-enabled account** as `ACCOUNTADMIN` (or `GLOBALORGADMIN` on an organization account). Org-usage grants fail from a regular account without ORGADMIN.

## Prerequisites

- Terraform >= 1.5
- An existing warehouse the export user may use
- Admin user + key-pair that can create users/roles and grant SNOWFLAKE database roles

## Apply

```bash
cd snowflake
terraform init
terraform apply \
  -var='organization_name=...' \
  -var='account_name=...' \
  -var='admin_user=...' \
  -var='admin_private_key=...' \
  -var='warehouse=COMPUTE_WH'
```

`SNOWFLAKE_USER` / `SNOWFLAKE_PRIVATE_KEY` / `SNOWFLAKE_ORGANIZATION_NAME` / `SNOWFLAKE_ACCOUNT_NAME` also work for the provider.

## Outputs

- `user_name`, `role_name`, `warehouse`
- `account_identifier` — `organization-account` (for JDBC / FinOps tools)
- `host` — `{account_identifier}.snowflakecomputing.com`
- `private_key_pem` (sensitive) — PKCS#8 private key for the service user

The private key is generated in Terraform state. Store it in a secret manager after apply.

## Billing views (SQL, not HTTP)

Connect with key-pair JWT as the service user, role `BILLING_EXPORT`, warehouse from outputs. Database `SNOWFLAKE`.

| View | Grain | Role |
| --- | --- | --- |
| [`SNOWFLAKE.ORGANIZATION_USAGE.USAGE_IN_CURRENCY_DAILY`](https://docs.snowflake.com/en/sql-reference/organization-usage/usage_in_currency_daily) | account × day × SKU | Invoice `$` (`USAGE_IN_CURRENCY`) and credits |
| [`SNOWFLAKE.ORGANIZATION_USAGE.WAREHOUSE_METERING_HISTORY`](https://docs.snowflake.com/en/sql-reference/organization-usage/warehouse_metering_history) | warehouse × hour | Compute credits (`CREDITS_USED_COMPUTE`) |
| [`SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY`](https://docs.snowflake.com/en/sql-reference/account-usage/query_attribution_history) | query | Credit split (compute + query acceleration). Latency up to 8h. Not Adaptive Warehouses. |
| [`SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY`](https://docs.snowflake.com/en/sql-reference/account-usage/query-history) | query | User / database / schema / tag / warehouse size |

`USAGE_IN_CURRENCY_DAILY` and warehouse metering are **organization-wide**. Query views are **this account only**. Bound every scan on a time column (`USAGE_DATE` / `START_TIME`).

```sql
SELECT
  USAGE_DATE,
  ACCOUNT_NAME,
  ACCOUNT_LOCATOR,
  SERVICE_TYPE,
  BILLING_TYPE,
  USAGE_IN_CURRENCY,
  USAGE,
  CURRENCY,
  IS_ADJUSTMENT
FROM SNOWFLAKE.ORGANIZATION_USAGE.USAGE_IN_CURRENCY_DAILY
WHERE USAGE_DATE >= '2026-01-01' AND USAGE_DATE < '2026-02-01';
```

## Data output

**USAGE_IN_CURRENCY_DAILY** (authoritative `$`):

| Field | Type | Notes |
| --- | --- | --- |
| `USAGE_DATE` | date | UTC day |
| `USAGE_IN_CURRENCY` | number | Invoice amount |
| `CURRENCY` | string | Contract currency |
| `USAGE` | number | Credits, TB, … (`RATING_TYPE`) |
| `SERVICE_TYPE`, `BILLING_TYPE`, `RATING_TYPE` | string | SKU / charge class |
| `ACCOUNT_NAME`, `ACCOUNT_LOCATOR`, `ORGANIZATION_NAME` | string | Account |
| `REGION`, `SERVICE_LEVEL` | string | Region / edition |
| `IS_ADJUSTMENT` | bool | Adjustment lines |
| `CONTRACT_NUMBER`, `BALANCE_SOURCE` | string | Contract |

**WAREHOUSE_METERING_HISTORY**: `START_TIME`, `WAREHOUSE_ID`, `WAREHOUSE_NAME`, `ACCOUNT_LOCATOR`, `ACCOUNT_NAME`, `CREDITS_USED_COMPUTE`.

**QUERY_ATTRIBUTION_HISTORY**: `QUERY_ID`, `WAREHOUSE_ID`, `WAREHOUSE_NAME`, `CREDITS_ATTRIBUTED_COMPUTE`, `CREDITS_USED_QUERY_ACCELERATION`, `START_TIME`. Does not include warehouse idle time.

**QUERY_HISTORY**: `QUERY_ID`, `USER_NAME`, `DATABASE_NAME`, `SCHEMA_NAME`, `QUERY_TAG`, `QUERY_HASH`, `WAREHOUSE_SIZE`, `START_TIME`.

A FinOps join: allocate each day’s UICD `$` to queries in proportion to QAH credits; leftover credits become unattributed lines. Totals per `(account_locator, usage_day)` must still match UICD.

If your org uses the newer organization account, grant `GRANT APPLICATION ROLE SNOWFLAKE.ORGANIZATION_BILLING_VIEWER` (and `ORGANIZATION_USAGE_VIEWER`) instead of / in addition to the database roles in [`main.tf`](main.tf).

## Official docs

- [USAGE_IN_CURRENCY_DAILY](https://docs.snowflake.com/en/sql-reference/organization-usage/usage_in_currency_daily)
- [WAREHOUSE_METERING_HISTORY](https://docs.snowflake.com/en/sql-reference/organization-usage/warehouse_metering_history)
- [QUERY_ATTRIBUTION_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/query_attribution_history)
- [SNOWFLAKE database roles](https://docs.snowflake.com/en/sql-reference/snowflake-db-roles)
- [Access control for cost data](https://docs.snowflake.com/en/user-guide/cost-access-control)
- [Key-pair authentication](https://docs.snowflake.com/en/user-guide/key-pair-auth)
- [snowflake_service_user](https://registry.terraform.io/providers/snowflakedb/snowflake/latest/docs/resources/service_user)
