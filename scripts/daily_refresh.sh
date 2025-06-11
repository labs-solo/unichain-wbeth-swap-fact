#!/bin/bash
# Daily refresh script for UniChain WBTC/ETH swap fact pipeline
# Orchestrates all ETL steps as specified in SPEC section 5

set -e  # Exit on any error

echo "🌅 Starting daily refresh at $(date)"
echo "======================================"

# Warn if any environment variable still uses placeholder values
warn_placeholders() {
    local flagged=0
    if [ "${HOOKED_POOL}" = "0x4107...e1f" ]; then
        echo "⚠️  HOOKED_POOL uses placeholder address" >&2
        flagged=1
    fi
    if [ "${STATIC_POOL}" = "0x51f9...3496e" ]; then
        echo "⚠️  STATIC_POOL uses placeholder address" >&2
        flagged=1
    fi
    if [[ "${RPC_URL}" == *"YOUR_ALCHEMY_KEY_HERE"* ]]; then
        echo "⚠️  RPC_URL contains placeholder API key" >&2
        flagged=1
    fi
    if [[ "${RPC_WS}" == *"YOUR_ALCHEMY_KEY_HERE"* ]]; then
        echo "⚠️  RPC_WS contains placeholder API key" >&2
        flagged=1
    fi
    [ $flagged -eq 1 ] && echo "🚨 Please update your .env file with real values." >&2
}

warn_placeholders

# Database connection parameters
DB_HOST=${PGHOST:-postgres}
DB_PORT=${PGPORT:-5432}  
DB_NAME=${PGDATABASE:-postgres}
DB_USER=${PGUSER:-postgres}

# Step 1: Catch-up HyperIndex
echo "📈 Step 1: Catching up HyperIndex..."
if command -v hyperindex >/dev/null 2>&1; then
    hyperindex catchup || echo "⚠️  HyperIndex catchup failed or not available"
else
    echo "⚠️  HyperIndex command not found - assuming it's running in separate container"
fi

# Step 2: Refresh materialized token-price view
echo "💰 Step 2: Refreshing token price view..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
REFRESH MATERIALIZED VIEW CONCURRENTLY token_prices_usd_day;
" || echo "⚠️  Price view refresh failed - view may not exist yet"

# Step 3: Label enrichment
echo "🏷️  Step 3: Running label enrichment..."

# Run contract marking script
echo "   3a: Marking contracts vs EOAs..."
if command -v python3 >/dev/null 2>&1; then
    python3 scripts/mark_contracts.py || echo "⚠️  Contract marking failed"
else
    echo "⚠️  Python3 not available - skipping contract marking"
fi

# TODO: Import new rows to address_labels (periodic CSV or upstream Dune dump)
echo "   3b: TODO - Import fresh address labels from Dune CSV"

# Step 4: Fetch receipts for new transactions
echo "🧾 Step 4: Fetching transaction receipts..."

# Find new transactions that need receipts
NEW_TX=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc "
SELECT encode(tx_hash,'hex') 
FROM raw_unichain_swaps
WHERE tx_hash NOT IN (SELECT tx_hash FROM tx_gas)
LIMIT 1000;  -- Limit to avoid overwhelming the RPC
")

if [ -n "$NEW_TX" ]; then
    echo "📥 Found $(echo "$NEW_TX" | wc -l) new transactions to fetch receipts for..."
    
    if command -v python3 >/dev/null 2>&1; then
        # Pass transaction hashes to receipt fetcher
        echo "$NEW_TX" | python3 scripts/fetch_receipts.py
        
        # Import receipt data if file was created
        if [ -f "tx_receipts.csv" ]; then
            echo "📊 Importing receipt data..."
            psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
            \COPY tx_gas(tx_hash, gas_used, gas_price) 
            FROM 'tx_receipts.csv' 
            CSV HEADER
            DELIMITER ',' 
            NULL '';
            "
            
            # Clean up temporary file
            rm -f tx_receipts.csv
            
            IMPORTED_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc "
            SELECT COUNT(*) FROM tx_gas;
            ")
            echo "✅ Imported gas data. Total tx_gas records: $IMPORTED_COUNT"
        else
            echo "⚠️  Receipt CSV file not created"
        fi
    else
        echo "⚠️  Python3 not available - skipping receipt fetching"
    fi
else
    echo "✅ No new transactions found - all receipts up to date"
fi

# Step 5: Insert new facts
echo "📊 Step 5: Inserting new swap facts..."

# Get count before insert
FACTS_BEFORE=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc "
SELECT COUNT(*) FROM labs_solo.pool_swap_fact_unichain;
")

# Run fact insert SQL
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f sql/ddl/02_fact_insert.sql

# Get count after insert
FACTS_AFTER=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc "
SELECT COUNT(*) FROM labs_solo.pool_swap_fact_unichain;
")

NEW_FACTS=$((FACTS_AFTER - FACTS_BEFORE))
echo "✅ Inserted $NEW_FACTS new facts. Total facts: $FACTS_AFTER"

# Step 6: Export to CSV
echo "📤 Step 6: Exporting to CSV..."
bash scripts/export_to_csv.sh

# Print final summary
echo ""
echo "🎉 Daily refresh complete at $(date)"
echo "======================================"
echo "📊 Final statistics:"

# Print table counts
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT 
    'raw_unichain_swaps' as table_name,
    COUNT(*) as row_count
FROM raw_unichain_swaps
UNION ALL
SELECT 
    'tx_gas',
    COUNT(*)
FROM tx_gas  
UNION ALL
SELECT 
    'address_labels',
    COUNT(*)
FROM address_labels
UNION ALL
SELECT 
    'pool_swap_fact_unichain',
    COUNT(*)
FROM labs_solo.pool_swap_fact_unichain
ORDER BY table_name;
"

# Print most recent swaps
echo "🔄 Most recent swaps:"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT 
    block_time,
    encode(pool_address, 'hex') as pool,
    flow_source,
    is_contract
FROM labs_solo.pool_swap_fact_unichain
ORDER BY block_time DESC
LIMIT 5;
"

echo "✨ Ready for manual Dune upload!"
echo "💡 Next: Upload swap_fact_$(date +%Y%m%d).csv to Dune labs_solo.pool_swap_fact_unichain" 