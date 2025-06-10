-- Materialized view for daily token USD prices
-- This view provides USD prices for WBTC and ETH on each day
-- Data sources: ETH/USDC and WBTC/USDC pools on major DEXs

CREATE MATERIALIZED VIEW IF NOT EXISTS token_prices_usd_day AS
WITH price_sources AS (
    -- ETH/USDC prices from major pools
    SELECT 
        block_time::DATE as price_date,
        '\x0000000000000000000000000000000000000000'::BYTEA as token_address, -- ETH placeholder
        'ETH' as symbol,
        -- Calculate ETH price from USDC swaps (simplified)
        AVG(
            CASE 
                WHEN token0 = '\xA0b86991c431e82e9E7C3b0e7C3e1a7E93d5d3a6F'::BYTEA -- USDC as token0
                THEN ABS(amount0::NUMERIC) / ABS(amount1::NUMERIC) * 1e12 -- USDC has 6 decimals, ETH has 18
                WHEN token1 = '\xA0b86991c431e82e9E7C3b0e7C3e1a7E93d5d3a6F'::BYTEA -- USDC as token1  
                THEN ABS(amount1::NUMERIC) / ABS(amount0::NUMERIC) * 1e12
                ELSE NULL
            END
        ) as price_usd
    FROM raw_unichain_swaps
    WHERE (
        token0 = '\xA0b86991c431e82e9E7C3b0e7C3e1a7E93d5d3a6F'::BYTEA OR -- USDC
        token1 = '\xA0b86991c431e82e9E7C3b0e7C3e1a7E93d5d3a6F'::BYTEA
    )
    AND (
        token0 = '\xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'::BYTEA OR -- WETH
        token1 = '\xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'::BYTEA
    )
    GROUP BY price_date
    
    UNION ALL
    
    -- WBTC/USDC prices from major pools
    SELECT 
        block_time::DATE as price_date,
        '\x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599'::BYTEA as token_address, -- WBTC
        'WBTC' as symbol,
        -- Calculate WBTC price from USDC swaps
        AVG(
            CASE 
                WHEN token0 = '\xA0b86991c431e82e9E7C3b0e7C3e1a7E93d5d3a6F'::BYTEA -- USDC as token0
                THEN ABS(amount0::NUMERIC) / ABS(amount1::NUMERIC) * 1e10 -- USDC has 6 decimals, WBTC has 8
                WHEN token1 = '\xA0b86991c431e82e9E7C3b0e7C3e1a7E93d5d3a6F'::BYTEA -- USDC as token1
                THEN ABS(amount1::NUMERIC) / ABS(amount0::NUMERIC) * 1e10
                ELSE NULL
            END
        ) as price_usd
    FROM raw_unichain_swaps  
    WHERE (
        token0 = '\xA0b86991c431e82e9E7C3b0e7C3e1a7E93d5d3a6F'::BYTEA OR -- USDC
        token1 = '\xA0b86991c431e82e9E7C3b0e7C3e1a7E93d5d3a6F'::BYTEA
    )
    AND (
        token0 = '\x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599'::BYTEA OR -- WBTC
        token1 = '\x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599'::BYTEA
    )
    GROUP BY price_date
),
-- Fill missing days with latest available price
daily_prices AS (
    SELECT 
        d.date_val as price_date,
        t.token_address,
        t.symbol,
        COALESCE(
            ps.price_usd,
            LAG(ps.price_usd) IGNORE NULLS OVER (
                PARTITION BY t.token_address 
                ORDER BY d.date_val
            )
        ) as price_usd
    FROM (
        SELECT generate_series(
            (SELECT MIN(price_date) FROM price_sources),
            CURRENT_DATE,
            '1 day'::INTERVAL
        )::DATE as date_val
    ) d
    CROSS JOIN (
        SELECT DISTINCT token_address, symbol 
        FROM price_sources
    ) t
    LEFT JOIN price_sources ps ON ps.price_date = d.date_val 
        AND ps.token_address = t.token_address
)
SELECT 
    price_date,
    token_address,
    symbol,
    price_usd
FROM daily_prices
WHERE price_usd IS NOT NULL;

-- Index for fast lookups
CREATE UNIQUE INDEX IF NOT EXISTS idx_token_prices_token_date 
ON token_prices_usd_day(token_address, price_date);

-- Refresh command (to be run by daily_refresh.sh)
-- REFRESH MATERIALIZED VIEW CONCURRENTLY token_prices_usd_day; 