# 📋 Specification: UniChain WBTC/ETH Swap-Fact Pipeline

> **Goal:** Produce `swap_fact_YYYYMMDD.csv` every 24 hours, containing one enriched row per swap in the two UniChain WBTC/ETH 0.05% pools (hooked vs. static). The CSV is uploaded to Dune under `labs_solo.pool_swap_fact_unichain` for analytics and dashboards.

---

## 1. 🎯 Scope & Requirements

| Item | Requirement |
| :--- | :--- |
| **Pools Tracked** | • **Hooked (AEGIS_DFM):** `0x4107…e1f` <br> • **Static:** `0x51f9…3496e` |
| **Historical Depth** | Re-index from pool-creation block to the latest head. |
| **Refresh Cadence** | Once per calendar day at **02:00 UTC** (cron). |
| **CSV Size Limit** | **≤ 500 MB** per file (Dune upload limit). Split by month if exceeded. |
| **Columns Required** | See **§4 Schema** (13 columns). |
| **Data Sources** | • UniChain full node (Alchemy RPC & WSS) <br> • ETH/WBTC price pools for USD conversion <br> • Blockscout receipt API <br> • Dune + custom address-labels CSV. |
| **Infra Footprint** | Single `docker-compose` stack: Postgres 16, HyperIndex container, Alpine cron container. |
| **Reproducibility** | `Dockerfile` pins exact `pnpm` + lockfile; integrity checks are enforced. |
| **Open-Data Compliance**| No paid APIs except the free Alchemy tier; everything else is community/on-chain. |

---

## 2. 🌊 High-Level Pipeline

```mermaid
flowchart TD
    A["💧 WebSocket RPC<br>Alchemy"] -->|"Swap Logs"| B["📦 HyperIndex<br>raw_unichain_swaps"]
    A -->|"eth_getTransactionReceipt"| C["🧾 tx_gas"]
    A -->|"WBTC/USDC<br>ETH/USDC Swaps"| D["💹 token_prices_usd_day"]
    E["🏷️ address_labels<br>Dune + CSV"] --> F["✨ Enrichment SQL"]
    B --> F
    C --> F
    D --> F
    F --> G["📊 pool_swap_fact_unichain"]
    G --> H["📄 CSV Export<br>swap_fact_YYYYMMDD.csv"]
    H --> I["☁️ Dune Upload"]
```

---

## 3. 🐳 Container Stack (`docker-compose.yml`)

| Service | Image / Build | Purpose |
| :--- | :--- | :--- |
| `postgres` | `postgres:16-alpine` | Durable time-series store & joins. |
| `hyperindex` | Local build from `enviodev/uniswap-v4-indexer` | Streams swaps into Postgres in real time. |
| `refresher` | `alpine:3.19` with `crond` | Executes the daily refresh script (`scripts/daily_refresh.sh`). |
| `network` | Docker bridge `etl_net` | Isolates containers for security and stability. |
| `volumes` | `pgdata`, `hyperindex_cache` | Ensures persistence for Postgres data and ABI cache. |

---

## 4. 📈 Fact-Table Schema (`labs_solo.pool_swap_fact_unichain`)

| Column | Type | Description |
| :--- | :--- | :--- |
| `block_time` | `TIMESTAMPTZ` | Timestamp of the swap. |
| `tx_hash` | `BYTEA` | The transaction hash. |
| `log_index` | `INT` | Position of the event log within the transaction. |
| `pool_address` | `BYTEA` | The address of the pool contract. |
| `token0`, `token1` | `BYTEA` | Addresses of the two token contracts in the pool. |
| `amount0`, `amount1`| `NUMERIC` | Raw token deltas from the swap. |
| `price0_usd`, `price1_usd` | `NUMERIC` | USD prices for each token at the time of the swap (daily granularity). |
| `trader` | `BYTEA` | The `msg.sender` of the swap (EOA or contract). |
| `is_contract` | `BOOLEAN` | A flag indicating if the trader is a contract (via bytecode check). |
| `flow_source` | `TEXT` | Classification of the trader (e.g., EOA, Aggregator, MEV). |
| `hop_index` | `INT` | The 1-based index of this swap within a multi-hop trade. |
| `gas_used` | `INT` | The total gas used for the transaction. |

> **Composite Primary Key:** `(tx_hash, log_index)`

**Indices:**
- `(pool_address, block_time)`
- `(flow_source)`
- `(tx_hash, hop_index)`

---

## 5. ⚙️ ETL Steps (`daily_refresh.sh`)

1.  **Catch-up HyperIndex**
    ```bash
    docker compose exec hyperindex hyperindex catchup
    ```
2.  **Refresh Materialized Token-Price View**
    ```sql
    REFRESH MATERIALIZED VIEW CONCURRENTLY token_prices_usd_day;
    ```
3.  **Label Enrichment**
    - Import new rows to `address_labels` (from CSV or Dune).
    - Run `scripts/mark_contracts.py` to flag new addresses.
4.  **Fetch Receipts**
    ```bash
    # Get new transaction hashes
    NEW_TX=$(psql -Atc "SELECT encode(tx_hash,'hex') FROM raw_unichain_swaps EXCEPT SELECT encode(tx_hash,'hex') FROM tx_gas;")
    # Fetch and import gas data
    echo "$NEW_TX" | python scripts/fetch_receipts.py
    psql -c "\copy tx_gas FROM 'tx_receipts.csv' CSV HEADER"
    ```
5.  **Insert New Facts**
    - Run `sql/ddl/02_fact_insert.sql` (`INSERT … ON CONFLICT DO NOTHING`).
6.  **Export to CSV**
    ```bash
    OUT="swap_fact_$(date +%Y%m%d).csv"
    psql -c "\COPY (SELECT * FROM labs_solo.pool_swap_fact_unichain) TO '$OUT' CSV HEADER"
    ```
7.  **Upload to Dune**
    - Manual UI upload or via `dune_api`.

---

## 6. 📁 Code & Config Layout

```
repo/
├─ infra/
│   └─ hyperindex/
│       ├─ Dockerfile            # Builds the local hyperindex image
│       ├─ config.yaml           # Defines chain, contracts, and mappings
│       └─ mappings.ts           # The TypeScript swap handler logic
├─ sql/
│   ├─ ddl/
│   │   ├─ 00_raw_swaps.sql      # Schema for raw swap data
│   │   ├─ 01_fact_table.sql     # Schema for the final fact table
│   │   └─ 02_fact_insert.sql    # The main ETL insertion logic
│   └─ views/
│       └─ token_prices_usd_day.sql # Materialized view for daily prices
├─ scripts/
│   ├─ init_schema.sh           # Initializes the database schema
│   ├─ mark_contracts.py        # Flags addresses as EOA or contract
│   ├─ fetch_receipts.py        # Fetches transaction gas data
│   ├─ export_to_csv.sh         # Exports the fact table to a CSV
│   └─ daily_refresh.sh         # The main daily cron script
├─ docker-compose.yml
├─ .env.template        # sample values to copy into `.env`
└─ README.md
```

---

## 7. 🔑 Environment Variables (`.env`)

```dotenv
# Alchemy RPC endpoints for UniChain
RPC_URL="https://unichain-mainnet.g.alchemy.com/v2/<ALCHEMY_KEY>"
RPC_WS="wss://unichain-mainnet.g.alchemy.com/v2/<ALCHEMY_KEY>"

# PostgreSQL connection details
DATABASE_URL="postgres://postgres:secret@postgres:5432/postgres"
POSTGRES_PASSWORD="secret"

# Chain and Pool configuration
CHAIN_ID=11877
HOOKED_POOL="0x4107…e1f"
STATIC_POOL="0x51f9…3496e"
```
> `.env.template` is version-controlled as a reference. Copy it to `.env` and
> update the values. The runtime services read variables from `.env`.

---

## 8. 🚀 CI/CD (Optional)

- **GitHub Actions:**
  - `sql-lint.yml`: Runs `sqlfluff` on pull requests to maintain SQL quality.
  - `docker-build.yml`: Builds the `hyperindex-local` image to ensure the `Dockerfile` remains valid.
- **Artifact Storage:** Attach the nightly CSV to a GitHub Release as a backup.

---

## 9. ✅ Success Criteria

-   **Backfill:** Initial backfill completes without errors, and `SELECT COUNT(*)` matches or exceeds the known swap count in the pools.
-   **Cron Job:** The daily cron runs at 02:00 UTC, exporting a fresh CSV with a matching timestamp.
-   **Dune Refresh:** The Dune table is updated (manually or via API), and dashboards reflect the new day's data by 02:15 UTC.
-   **File Size:** The daily CSV remains under 500 MB (or monthly partitioning is implemented).
-   **Data Integrity:** No missing columns; analysts can compute key metrics like daily volume, flow-source shares, multi-hop paths, top traders, and gas costs.

---

## 10. ❓ Open Questions / TODO

- [ ] **Confirm Chain ID:** Verify the exact `chainId` for UniChain mainnet (assumed `11877`).
- [ ] **Automate Dune Upload:** Decide whether to automate the Dune upload via its API or maintain the manual process.
- [ ] **Future Columns:** Consider adding `surge_fee_bps` & `cap_event` columns if the AEGIS DFM hook begins emitting additional events.

> Once these items are addressed, this specification is implementation-complete and the pipeline is fully reproducible from end-to-end.
