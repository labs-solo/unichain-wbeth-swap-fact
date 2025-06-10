#!/usr/bin/env python3
"""
mark_contracts.py - Mark addresses as contracts or EOAs via bytecode check
Part of UniChain WBTC/ETH swap fact pipeline

This script:
1. Finds unlabeled addresses in the address_labels table
2. Checks each address for bytecode via RPC
3. Updates is_contract flag based on bytecode presence
"""

import os
import sys
import psycopg2
import requests
import json
import time
from typing import List, Tuple
from urllib.parse import urlparse

# Configuration
RPC_URL = os.getenv('RPC_URL')
DATABASE_URL = os.getenv('DATABASE_URL')
BATCH_SIZE = 100
DELAY_BETWEEN_BATCHES = 1.0  # seconds to avoid rate limiting

def get_database_connection():
    """Get database connection from DATABASE_URL"""
    if not DATABASE_URL:
        raise ValueError("DATABASE_URL environment variable not set")
    
    return psycopg2.connect(DATABASE_URL)

def get_unlabeled_addresses(conn) -> List[str]:
    """Get addresses that don't have is_contract flag set"""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT DISTINCT encode(address, 'hex') as address_hex
            FROM address_labels 
            WHERE is_contract IS NULL
            LIMIT %s
        """, (BATCH_SIZE,))
        
        return [row[0] for row in cur.fetchall()]

def check_contract_bytecode(address: str) -> bool:
    """Check if address has bytecode (is a contract)"""
    if not RPC_URL:
        print("⚠️  RPC_URL not set, skipping bytecode checks")
        return False
    
    try:
        payload = {
            "jsonrpc": "2.0",
            "method": "eth_getCode",
            "params": [f"0x{address}", "latest"],
            "id": 1
        }
        
        response = requests.post(RPC_URL, json=payload, timeout=10)
        response.raise_for_status()
        
        result = response.json()
        if 'error' in result:
            print(f"⚠️  RPC error for {address}: {result['error']}")
            return False
        
        # Contract if bytecode is not empty (more than just "0x")
        bytecode = result.get('result', '0x')
        return bytecode != '0x' and len(bytecode) > 2
        
    except Exception as e:
        print(f"⚠️  Error checking {address}: {e}")
        return False

def update_contract_flags(conn, address_flags: List[Tuple[str, bool]]):
    """Update is_contract flags in database"""
    with conn.cursor() as cur:
        for address_hex, is_contract in address_flags:
            cur.execute("""
                UPDATE address_labels 
                SET is_contract = %s, updated_at = NOW()
                WHERE address = decode(%s, 'hex')
            """, (is_contract, address_hex))
    
    conn.commit()

def ensure_addresses_exist(conn, addresses: List[str]):
    """Ensure all sender addresses exist in address_labels table"""
    with conn.cursor() as cur:
        # Get addresses that need to be inserted
        placeholders = ','.join(['%s'] * len(addresses))
        cur.execute(f"""
            SELECT encode(sender, 'hex') as sender_hex
            FROM (
                VALUES {','.join([f"(decode('{addr}', 'hex'))" for addr in addresses])}
            ) AS addrs(sender)
            WHERE NOT EXISTS (
                SELECT 1 FROM address_labels al 
                WHERE al.address = addrs.sender
            )
        """)
        
        missing_addresses = [row[0] for row in cur.fetchall()]
        
        # Insert missing addresses
        if missing_addresses:
            print(f"📝 Inserting {len(missing_addresses)} new addresses into address_labels...")
            for addr in missing_addresses:
                cur.execute("""
                    INSERT INTO address_labels (address, flow_source) 
                    VALUES (decode(%s, 'hex'), 'Other')
                    ON CONFLICT (address) DO NOTHING
                """, (addr,))
    
    conn.commit()

def get_sender_addresses_from_swaps(conn, limit: int = 1000) -> List[str]:
    """Get sender addresses from raw swaps that aren't in address_labels yet"""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT DISTINCT encode(sender, 'hex') as sender_hex
            FROM raw_unichain_swaps r
            WHERE NOT EXISTS (
                SELECT 1 FROM address_labels al 
                WHERE al.address = r.sender
            )
            LIMIT %s
        """, (limit,))
        
        return [row[0] for row in cur.fetchall()]

def main():
    print("🔍 Starting contract marking process...")
    
    if not RPC_URL:
        print("⚠️  RPC_URL not set, will only process existing address_labels")
    
    try:
        conn = get_database_connection()
        
        # First, ensure all sender addresses from swaps are in address_labels
        sender_addresses = get_sender_addresses_from_swaps(conn)
        if sender_addresses:
            print(f"📥 Found {len(sender_addresses)} new sender addresses from swaps")
            ensure_addresses_exist(conn, sender_addresses)
        
        # Now process unlabeled addresses
        total_processed = 0
        
        while True:
            addresses = get_unlabeled_addresses(conn)
            if not addresses:
                break
            
            print(f"🔄 Processing batch of {len(addresses)} addresses...")
            
            # Check bytecode for each address
            address_flags = []
            for i, address in enumerate(addresses):
                is_contract = check_contract_bytecode(address)
                address_flags.append((address, is_contract))
                
                if (i + 1) % 10 == 0:
                    print(f"   Checked {i + 1}/{len(addresses)} addresses...")
            
            # Update database
            update_contract_flags(conn, address_flags)
            
            contract_count = sum(1 for _, is_contract in address_flags if is_contract)
            eoa_count = len(address_flags) - contract_count
            
            print(f"✅ Updated {len(address_flags)} addresses: {contract_count} contracts, {eoa_count} EOAs")
            
            total_processed += len(addresses)
            
            # Rate limiting
            if len(addresses) == BATCH_SIZE:
                print(f"💤 Sleeping {DELAY_BETWEEN_BATCHES}s to respect rate limits...")
                time.sleep(DELAY_BETWEEN_BATCHES)
        
        print(f"🎉 Contract marking complete! Processed {total_processed} addresses total.")
        
        # Print summary statistics
        with conn.cursor() as cur:
            cur.execute("""
                SELECT 
                    flow_source,
                    COUNT(*) as total,
                    SUM(CASE WHEN is_contract THEN 1 ELSE 0 END) as contracts,
                    SUM(CASE WHEN NOT is_contract THEN 1 ELSE 0 END) as eoas
                FROM address_labels 
                WHERE is_contract IS NOT NULL
                GROUP BY flow_source
                ORDER BY total DESC
            """)
            
            print("\n📊 Address summary by flow source:")
            for row in cur.fetchall():
                flow_source, total, contracts, eoas = row
                print(f"   {flow_source}: {total} total ({contracts} contracts, {eoas} EOAs)")
        
        conn.close()
        
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 