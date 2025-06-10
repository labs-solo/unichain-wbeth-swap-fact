#!/bin/bash
# CSV export script for UniChain WBTC/ETH swap fact data
# Exports labs_solo.pool_swap_fact_unichain to timestamped CSV file

set -e  # Exit on any error

echo "📤 Starting CSV export process..."

# Database connection parameters  
DB_HOST=${PGHOST:-postgres}
DB_PORT=${PGPORT:-5432}
DB_NAME=${PGDATABASE:-postgres}
DB_USER=${PGUSER:-postgres}

# Generate timestamped filename
TIMESTAMP=$(date +%Y%m%d)
OUTPUT_FILE="swap_fact_${TIMESTAMP}.csv"

echo "📊 Exporting fact table to ${OUTPUT_FILE}..."

# Check if fact table has data
ROW_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc "
SELECT COUNT(*) FROM labs_solo.pool_swap_fact_unichain;
")

if [ "$ROW_COUNT" -eq 0 ]; then
    echo "⚠️  Fact table is empty! Creating empty CSV file..."
    # Create CSV with headers only
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
    \COPY (
        SELECT 
            block_time,
            encode(tx_hash, 'hex') as tx_hash,
            log_index,
            encode(pool_address, 'hex') as pool_address,
            encode(token0, 'hex') as token0,
            encode(token1, 'hex') as token1,
            amount0,
            amount1,
            price0_usd,
            price1_usd,
            encode(trader, 'hex') as trader,
            is_contract,
            flow_source,
            hop_index,
            gas_used
        FROM labs_solo.pool_swap_fact_unichain
        LIMIT 0
    ) TO '$OUTPUT_FILE' CSV HEADER;
    "
else
    echo "📋 Exporting $ROW_COUNT rows from fact table..."
    
    # Export with proper hex encoding for bytea fields
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
    \COPY (
        SELECT 
            block_time,
            encode(tx_hash, 'hex') as tx_hash,
            log_index,
            encode(pool_address, 'hex') as pool_address,
            encode(token0, 'hex') as token0,
            encode(token1, 'hex') as token1,
            amount0,
            amount1,
            price0_usd,
            price1_usd,
            encode(trader, 'hex') as trader,
            is_contract,
            flow_source,
            hop_index,
            gas_used
        FROM labs_solo.pool_swap_fact_unichain
        ORDER BY block_time, tx_hash, log_index
    ) TO '$OUTPUT_FILE' CSV HEADER;
    "
fi

# Check file size and warn if approaching Dune limit
FILE_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
FILE_SIZE_MB=$((FILE_SIZE / 1024 / 1024))

echo "📁 Export complete: ${OUTPUT_FILE} (${FILE_SIZE_MB} MB)"

# Warn if approaching 500MB Dune limit
if [ "$FILE_SIZE_MB" -gt 400 ]; then
    echo "⚠️  WARNING: File size ${FILE_SIZE_MB}MB is approaching Dune's 500MB limit!"
    echo "💡 Consider implementing monthly partitioning as mentioned in SPEC section 1."
fi

# Print summary statistics
echo "📊 Export summary:"
echo "   • File: ${OUTPUT_FILE}"
echo "   • Size: ${FILE_SIZE_MB} MB"
echo "   • Rows: ${ROW_COUNT}"

# Print sample of data for verification
if [ "$ROW_COUNT" -gt 0 ]; then
    echo "🔍 Sample data (first 3 rows):"
    head -n 4 "$OUTPUT_FILE" | column -t -s,
fi

# Print pool breakdown
echo "🏊 Pool breakdown:"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT 
    encode(pool_address, 'hex') as pool_address,
    COUNT(*) as swap_count,
    COUNT(DISTINCT encode(trader, 'hex')) as unique_traders
FROM labs_solo.pool_swap_fact_unichain
GROUP BY pool_address
ORDER BY swap_count DESC;
"

echo "✅ CSV export complete! Ready for Dune upload."
echo "🚀 Next steps:"
echo "   1. Review ${OUTPUT_FILE} for data quality"
echo "   2. Upload to Dune at labs_solo.pool_swap_fact_unichain"
echo "   3. Verify dashboard refresh" 