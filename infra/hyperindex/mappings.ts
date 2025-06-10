/**
 * HyperIndex mappings for UniChain WBTC/ETH swap indexing
 * Handles Swap events from Uniswap V4 PoolManager
 */

import { SwapEvent, Database } from '@hyperindex/core';

// Pool addresses from environment/config
const HOOKED_POOL = process.env.HOOKED_POOL || "0x4107...e1f";
const STATIC_POOL = process.env.STATIC_POOL || "0x51f9...3496e";

// WBTC and ETH token addresses (these will be the ones in the pools)
const WBTC_ADDRESS = "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599";
const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

/**
 * Handle Swap events from PoolManager
 * Only process swaps from our target WBTC/ETH pools
 */
export async function handleSwap(event: SwapEvent, db: Database): Promise<void> {
  const { 
    id: poolId,
    sender,
    amount0,
    amount1,
    sqrtPriceX96,
    liquidity,
    tick,
    fee
  } = event.params;

  // Convert pool ID (bytes32) to pool address for filtering
  // Note: In Uniswap V4, pool ID is derived from the pool key
  // We'll need to check if this swap is from one of our target pools
  const poolIdHex = poolId.toString();
  
  // For now, we'll index all swaps and filter later in the fact table
  // In production, you'd want to implement proper pool filtering here
  
  // Determine token addresses based on the pool
  // This is simplified - in reality you'd query the pool to get token0/token1
  let token0 = WBTC_ADDRESS;
  let token1 = WETH_ADDRESS;
  
  // Create the raw swap record
  const swapRecord = {
    id: `${event.chainId}_${event.blockNumber}_${event.logIndex}`,
    chain_id: event.chainId,
    block_number: event.blockNumber,  
    block_time: new Date(event.block.timestamp * 1000),
    tx_hash: event.transactionHash,
    log_index: event.logIndex,
    
    // Pool info
    pool_id: poolId,
    pool_address: poolId, // Simplified - would need proper mapping
    token0: token0,
    token1: token1,
    
    // Swap amounts (as received from event)
    amount0: amount0.toString(),
    amount1: amount1.toString(),
    
    // Price and liquidity info
    sqrt_price_x96: sqrtPriceX96.toString(),
    tick: tick,
    liquidity: liquidity.toString(),
    
    // Transaction context
    sender: sender,
    origin: event.transaction.from,
    
    // Metadata
    created_at: new Date()
  };

  // Insert into raw_unichain_swaps table
  await db.insert('raw_unichain_swaps', swapRecord);
  
  // Log for debugging
  console.log(`Indexed swap: ${swapRecord.id} from pool ${poolIdHex.slice(0, 10)}...`);
}

/**
 * Optional: Handle other events if needed
 */
export async function handleInitialize(event: any, db: Database): Promise<void> {
  // Handle pool initialization events if needed for tracking new pools
  console.log(`Pool initialized: ${event.params.id}`);
}

export async function handleModifyLiquidity(event: any, db: Database): Promise<void> {
  // Handle liquidity changes if needed for additional context
  // For now, we only care about swaps
} 