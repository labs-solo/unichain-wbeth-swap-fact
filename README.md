# UniChain WBTC/ETH Swap Fact Table 🚀

End-to-end ETL for building `labs_solo.pool_swap_fact_unichain`
— the canonical per-swap dataset powering our hooked-vs-static
volume dashboard on Dune.

## 📋 Overview

This pipeline indexes swap events from two UniChain WBTC/ETH pools:
- **Hooked Pool** (AEGIS_DFM): `0x4107...e1f` 
- **Static Pool**: `0x51f9...3496e`

Daily at 02:00 UTC, it produces enriched CSV files for Dune upload.

> For a complete breakdown of the architecture, schema, and ETL steps, please see the [**Full Specification (SPEC.md)**](./SPEC.md).

## 🏗️ Architecture

```
UniChain RPC → HyperIndex → Postgres → ETL Scripts → CSV → Dune
```

**Components:**
- `postgres:16-alpine` - Time-series storage
- `infra/hyperindex/` - Custom indexer for swap events  
- `scripts/` - Python/Bash ETL pipeline
- `sql/` - Schema definitions and views
- Alpine cron - Daily refresh scheduler

## 🚀 Quick Start

1. **Configure Environment**
   ```bash
   cp .env.template .env
   # Edit .env with your Alchemy RPC URLs and actual pool addresses
   ```
   **Important**: set `HOOKED_POOL`, `STATIC_POOL`, `RPC_URL` and `RPC_WS` to real
   values before starting the stack. The placeholders in `.env.template` will
   cause the pipeline to fail.

2. **Start Services**
   ```bash
   docker compose up -d
   ```

3. **Initialize Schema**
   ```bash
   docker compose exec refresher sh scripts/init_schema.sh
   ```

4. **Monitor Progress**
   ```bash
   docker compose logs -f hyperindex
   docker compose logs -f refresher
   ```

5. **Manual Export** (optional)
   ```bash
   docker compose exec refresher sh scripts/export_to_csv.sh
   ```

## 📊 Daily Process

Every day at 02:00 UTC, the system:
1. Catches up HyperIndex to latest block
2. Refreshes USD pricing materialized view
3. Marks new addresses as contracts/EOAs
4. Fetches transaction receipts for gas data
5. Inserts enriched facts into final table
6. Exports timestamped CSV: `swap_fact_YYYYMMDD.csv`

## 🔧 Manual Operations

- **Backfill**: `docker compose exec hyperindex hyperindex catchup`
- **Schema Reset**: `docker compose exec refresher sh scripts/init_schema.sh`
- **Contract Check**: `docker compose exec refresher python3 scripts/mark_contracts.py`

## 📁 File Structure

```
├── infra/hyperindex/     # HyperIndex config & mappings
├── sql/ddl/             # Schema definitions
├── sql/views/           # USD pricing view  
├── scripts/             # ETL automation
└── docker-compose.yml   # Container orchestration
```

## ⚠️ Requirements

- Docker & Docker Compose
- Alchemy API key for UniChain RPC access
- Actual pool addresses (placeholders in SPEC need updating)
- The environment variables `HOOKED_POOL`, `STATIC_POOL`, `RPC_URL` and
  `RPC_WS` **must** be filled in with real values in your `.env` file
  before running `docker compose up`.

## 🛠️ Running Scripts Locally

If you need to run the Python scripts outside of Docker, install the required
packages first:

```bash
pip install -r requirements.txt
```

## 🎯 Success Criteria

✅ **Implemented Features:**
- Complete SQL schema matching SPEC section 4
- All 5 required scripts for ETL pipeline
- Docker-compose with proper cron scheduling
- HyperIndex configuration for UniChain
- USD pricing via materialized views
- Contract vs EOA identification
- Gas usage tracking via receipts
- Timestamped CSV export with proper encoding

🔄 **Next Steps:**
1. Update pool addresses with actual values
2. Test with live UniChain data
3. Set up Dune API upload automation
4. Implement monthly partitioning if CSV > 500MB
