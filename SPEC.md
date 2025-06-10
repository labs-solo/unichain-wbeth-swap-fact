Specification — UniChain WBTC/ETH Swap-Fact Pipeline

Goal: produce swap_fact_YYYYMMDD.csv every 24 h, containing one enriched row per swap in the two UniChain WBTC/ETH 0.05 % pools (hooked vs static).
The CSV is uploaded to Dune under labs_solo.pool_swap_fact_unichain where analysts build dashboards.

⸻

1. Scope & Requirements

Item Requirement
Pools tracked • Hooked (AEGIS_DFM) 0x4107…e1f  • Static 0x51f9…3496e
Historical depth Re-index from pool-creation block → latest head.
Refresh cadence Once per calendar day at 02:00 UTC (cron).
CSV size limit ≤ 500 MB per file (Dune upload limit). Split by month if exceeded.
Columns required See §4 Schema (13 columns).
Data sources • UniChain full node (Alchemy RPC & WSS)  • ETH/WBTC price pools for USD conversion  • Blockscout receipt API  • Dune + custom address-labels CSV.
Infra footprint Single docker-compose stack: Postgres 16, HyperIndex container, Alpine cron container.
Reproducibility Dockerfile pins exact pnpm + lockfile; integrity checks ON.
Open-data compliance No paid APIs except free Alchemy Free tier; everything else community / on-chain.

⸻

2. High-Level Pipeline

flowchart TD
    A[WebSocket RPC<br/>Alchemy] -->|Swap logs| B[HyperIndex<br/>raw_unichain_swaps]
    A -->|eth_getTransactionReceipt| C[tx_gas]
    A -->|WBTC/USDC<br/>ETH/USDC swaps| D[token_prices_usd_day]
    E[address_labels<br/>(Dune + CSV)] --> F[enrichment SQL]
    B --> F
    C --> F
    D --> F
    F --> G[pool_swap_fact_unichain]
    G --> H[CSV export<br/>swap_fact_YYYYMMDD.csv]
    H --> I[Dune Upload]

⸻

3. Container Stack (docker-compose.yml)

Service Image / Build Purpose
postgres postgres:16-alpine Durable time-series store & joins
hyperindex local build from enviodev/uniswap-v4-indexer pinned tag; runs pnpm build with CHAIN_ID & RPC_URL envs Streams swaps into Postgres in real time
refresher alpine:3.19 with system crond Executes scripts/daily_refresh.sh
network Docker bridge etl_net Isolates containers
volumes pgdata, hyperindex_cache Postgres & ABI cache persistence

⸻

4. Fact-Table Schema (labs_solo.pool_swap_fact_unichain)

column type description
block_time TIMESTAMPTZ swap timestamp
tx_hash BYTEA transaction hash
log_index INT position inside tx
pool_address BYTEA pool ID
token0,token1 BYTEA token contracts
amount0,amount1 NUMERIC raw deltas
price0_usd,price1_usd NUMERIC USD prices at swap day
trader BYTEA msg.sender (EOA/contract)
is_contract BOOLEAN flag via bytecode check
flow_source TEXT EOA, Aggregator, CowSwap, MEV, CEX, Other
hop_index INT 1-n within tx
gas_used INT total gas for tx

Composite PK: (tx_hash, log_index).

Indices:
 • (pool_address, block_time)
 • (flow_source)
 • (tx_hash, hop_index)

⸻

5. ETL Steps (daily_refresh.sh)
1. Catch-up HyperIndex

docker compose exec hyperindex hyperindex catchup

 2. Refresh materialized token-price view
REFRESH MATERIALIZED VIEW CONCURRENTLY token_prices_usd_day;
 3. Label enrichment
 • import new rows to address_labels (periodic CSV or upstream Dune dump)
 • run scripts/mark_contracts.py to fill is_contract for unlabeled addresses.
 4. Fetch receipts

NEW_TX=$(psql -Atc "
  SELECT encode(tx_hash,'hex') FROM raw_unichain_swaps
  EXCEPT
  SELECT encode(tx_hash,'hex') FROM tx_gas;")
echo "$NEW_TX" | python scripts/fetch_receipts.py
\copy tx_gas FROM 'tx_receipts.csv' CSV HEADER

 5. Insert new facts
Run sql/ddl/02_fact_insert.sql (INSERT … ON CONFLICT DO NOTHING).
 6. Export

OUT="swap_fact_$(date +%Y%m%d).csv"
psql -c "\COPY (SELECT * FROM labs_solo.pool_swap_fact_unichain) TO '$OUT' CSV HEADER"

 7. Upload to Dune (manual UI or dune_api datasets upload).

⸻

6. Code & Config Layout

repo/
├─ infra/
│   └─ hyperindex/
│       ├─ Dockerfile            # builds hyperindex-local
│       ├─ config.yaml           # chain & mappings
│       └─ mappings.ts           # Swap handler
├─ sql/
│   ├─ ddl/
│   │   ├─ 00_raw_swaps.sql
│   │   ├─ 01_fact_table.sql
│   │   └─ 02_fact_insert.sql
│   └─ views/
│       └─ token_prices_usd_day.sql
├─ scripts/
│   ├─ init_schema.sh
│   ├─ mark_contracts.py
│   ├─ fetch_receipts.py
│   ├─ export_to_csv.sh
│   └─ daily_refresh.sh
├─ docker-compose.yml
├─ .env.template
└─ README.md

⸻

7. Environment Variables (.env)

RPC_URL=<https://unichain-mainnet.g.alchemy.com/v2/><ALCHEMY_KEY>
RPC_WS=wss://unichain-mainnet.g.alchemy.com/v2/<ALCHEMY_KEY>
DATABASE_URL=postgres://postgres:secret@postgres:5432/postgres
POSTGRES_PASSWORD=secret
CHAIN_ID=11877                # optional for codegen
HOOKED_POOL=0x4107…e1f
STATIC_POOL=0x51f9…3496e

.env.template is committed; .env is git-ignored.

⸻

8. CI / CD (optional)
 • GitHub Actions
 • sql-lint.yml → runs sqlfluff on PRs.
 • docker-build.yml → builds hyperindex-local image to ensure Dockerfile stays green.
 • Artifact: attach nightly CSV to a GitHub Release as backup.

⸻

9. Success Criteria
 • Initial back-fill completes without error; SELECT COUNT(*) shows ≥ swap count in pools.
 • Daily cron runs at 02:00 UTC, exports fresh CSV, file timestamp matches.
 • Dune table auto-refreshes (manual upload or API) and dashboards show new day’s data by 02:15 UTC.
 • CSV stays < 500 MB (or monthly partitioning implemented).
 • No missing columns; analysts can compute daily volume, flow-source shares, multi-hop paths, top traders, gas cost.

⸻

10. Open Questions / TODO
 1. Exact chainId for UniChain mainnet (11877 assumed) — confirm.
 2. Decide whether to automate Dune upload via API or keep manual.
 3. Future: add surge_fee_bps & cap_event columns if AEGIS DFM hook emits extra events.

Once these are cleared, the spec above is implementation-complete and reproducible end-to-end.
