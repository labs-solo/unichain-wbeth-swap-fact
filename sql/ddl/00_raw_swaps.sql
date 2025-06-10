-- Raw UniChain swaps table
-- This table is populated by HyperIndex from the Swap events
-- from both hooked and static WBTC/ETH pools

CREATE TABLE IF NOT EXISTS raw_unichain_swaps (
    -- Event identification
    id TEXT PRIMARY KEY,
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INT NOT NULL,
    
    -- Pool and token info
    pool_id BYTEA NOT NULL,
    pool_address BYTEA NOT NULL,
    token0 BYTEA NOT NULL,
    token1 BYTEA NOT NULL,
    
    -- Swap amounts (raw values from event)
    amount0 NUMERIC NOT NULL,
    amount1 NUMERIC NOT NULL,
    
    -- Price info
    sqrt_price_x96 NUMERIC NOT NULL,
    tick INT NOT NULL,
    liquidity NUMERIC NOT NULL,
    
    -- Transaction context
    sender BYTEA NOT NULL,
    origin BYTEA NOT NULL,
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indices for performance
CREATE INDEX IF NOT EXISTS idx_raw_swaps_pool_time ON raw_unichain_swaps(pool_address, block_time);
CREATE INDEX IF NOT EXISTS idx_raw_swaps_tx_hash ON raw_unichain_swaps(tx_hash);
CREATE INDEX IF NOT EXISTS idx_raw_swaps_block_time ON raw_unichain_swaps(block_time);
CREATE INDEX IF NOT EXISTS idx_raw_swaps_sender ON raw_unichain_swaps(sender);

-- Table for transaction gas data
CREATE TABLE IF NOT EXISTS tx_gas (
    tx_hash BYTEA PRIMARY KEY,
    gas_used INT NOT NULL,
    gas_price NUMERIC,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Address labels table for enrichment
CREATE TABLE IF NOT EXISTS address_labels (
    address BYTEA PRIMARY KEY,
    label TEXT,
    flow_source TEXT, -- EOA, Aggregator, CowSwap, MEV, CEX, Other
    is_contract BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_address_labels_flow_source ON address_labels(flow_source); 