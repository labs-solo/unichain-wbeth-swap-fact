-- Insert enriched swap facts from raw data
-- This query transforms raw_unichain_swaps into labs_solo.pool_swap_fact_unichain
-- with USD pricing, flow source classification, and hop indexing

INSERT INTO labs_solo.pool_swap_fact_unichain (
    block_time,
    tx_hash,
    log_index,
    pool_address,
    token0,
    token1,
    amount0,
    amount1,
    price0_usd,
    price1_usd,
    trader,
    is_contract,
    flow_source,
    hop_index,
    gas_used
)
WITH hop_numbered AS (
    -- Add hop index based on log_index order within each transaction
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY tx_hash ORDER BY log_index) as hop_index
    FROM raw_unichain_swaps r
    WHERE NOT EXISTS (
        -- Only insert new swaps (ON CONFLICT DO NOTHING equivalent)
        SELECT 1 FROM labs_solo.pool_swap_fact_unichain f 
        WHERE f.tx_hash = r.tx_hash AND f.log_index = r.log_index
    )
),
price_enriched AS (
    SELECT 
        h.*,
        -- USD pricing lookup from materialized view
        COALESCE(p0.price_usd, 0) as price0_usd,
        COALESCE(p1.price_usd, 0) as price1_usd
    FROM hop_numbered h
    LEFT JOIN token_prices_usd_day p0 ON p0.token_address = h.token0 
        AND p0.price_date = h.block_time::DATE
    LEFT JOIN token_prices_usd_day p1 ON p1.token_address = h.token1 
        AND p1.price_date = h.block_time::DATE
)
SELECT 
    pe.block_time,
    pe.tx_hash,
    pe.log_index,
    pe.pool_address,
    pe.token0,
    pe.token1,
    pe.amount0,
    pe.amount1,
    pe.price0_usd,
    pe.price1_usd,
    pe.sender as trader,
    COALESCE(al.is_contract, FALSE) as is_contract,
    COALESCE(al.flow_source, 'Other') as flow_source,
    pe.hop_index::INT,
    tg.gas_used
FROM price_enriched pe
LEFT JOIN address_labels al ON al.address = pe.sender
LEFT JOIN tx_gas tg ON tg.tx_hash = pe.tx_hash
ON CONFLICT (tx_hash, log_index) DO NOTHING; 