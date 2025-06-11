#!/usr/bin/env bash
set -eo pipefail

YEAR_MONTH=$(date -u +%Y_%m)
OUT="swap_fact_${YEAR_MONTH}.csv"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "\
  \COPY (
    SELECT
      block_time,
      encode(tx_hash,       'hex') AS tx_hash,
      log_index,
      encode(pool_address,  'hex') AS pool_address,
      encode(token0,        'hex') AS token0,
      encode(token1,        'hex') AS token1,
      amount0, amount1,
      price0_usd, price1_usd,
      encode(trader,        'hex') AS trader,
      is_contract,
      flow_source,
      hop_index,
      gas_used
    FROM   labs_solo.pool_swap_fact_unichain
    WHERE  date_trunc('month', block_time)
           = date_trunc('month', NOW() AT TIME ZONE 'UTC')
    ORDER  BY block_time, tx_hash, log_index
  ) TO '${OUT}' CSV HEADER"

ROWS=$(wc -l < "$OUT")
SIZE_MB=$(du -m "$OUT" | cut -f1)
echo "✅  ${OUT}:  rows=$((ROWS-1))  size=${SIZE_MB} MB"

if [ "$SIZE_MB" -gt 400 ]; then
  echo "⚠️   File size approaching Dune limit; consider weekly exports."
fi

