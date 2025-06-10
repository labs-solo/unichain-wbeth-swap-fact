-- Fact table: labs_solo.pool_swap_fact_unichain
-- This is the main analytical table with enriched swap data
-- Schema matches exactly the specification in section 4

CREATE SCHEMA IF NOT EXISTS labs_solo;

CREATE TABLE IF NOT EXISTS labs_solo.pool_swap_fact_unichain (
    -- Time and transaction identification
    block_time TIMESTAMPTZ NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INT NOT NULL,
    
    -- Pool and token information
    pool_address BYTEA NOT NULL,
    token0 BYTEA NOT NULL,
    token1 BYTEA NOT NULL,
    
    -- Swap amounts (raw deltas)
    amount0 NUMERIC NOT NULL,
    amount1 NUMERIC NOT NULL,
    
    -- USD pricing (at swap day)
    price0_usd NUMERIC,
    price1_usd NUMERIC,
    
    -- Trader information
    trader BYTEA NOT NULL, -- msg.sender (EOA/contract)
    is_contract BOOLEAN DEFAULT FALSE,
    flow_source TEXT, -- EOA, Aggregator, CowSwap, MEV, CEX, Other
    
    -- Multi-hop context
    hop_index INT NOT NULL, -- 1-n within tx
    
    -- Gas information
    gas_used INT,
    
    -- Composite Primary Key as specified
    PRIMARY KEY (tx_hash, log_index)
);

-- Indices as specified in section 4
CREATE INDEX IF NOT EXISTS idx_fact_pool_time ON labs_solo.pool_swap_fact_unichain(pool_address, block_time);
CREATE INDEX IF NOT EXISTS idx_fact_flow_source ON labs_solo.pool_swap_fact_unichain(flow_source);
CREATE INDEX IF NOT EXISTS idx_fact_tx_hop ON labs_solo.pool_swap_fact_unichain(tx_hash, hop_index);

-- Additional useful indices for analytics
CREATE INDEX IF NOT EXISTS idx_fact_block_time ON labs_solo.pool_swap_fact_unichain(block_time);
CREATE INDEX IF NOT EXISTS idx_fact_trader ON labs_solo.pool_swap_fact_unichain(trader);
CREATE INDEX IF NOT EXISTS idx_fact_is_contract ON labs_solo.pool_swap_fact_unichain(is_contract); 