#!/usr/bin/env python3
"""
fetch_receipts.py - Fetch transaction receipts for gas data
Part of UniChain WBTC/ETH swap fact pipeline

This script:
1. Reads transaction hashes from stdin (one per line)
2. Fetches receipts via RPC calls
3. Outputs CSV with tx_hash,gas_used,gas_price
"""

import os
import sys
import requests
import json
import csv
import time
from typing import Optional, Dict, Any

# Configuration
RPC_URL = os.getenv('RPC_URL')
BATCH_SIZE = 50
DELAY_BETWEEN_BATCHES = 0.5  # seconds
OUTPUT_FILE = 'tx_receipts.csv'

def fetch_receipt(tx_hash: str) -> Optional[Dict[str, Any]]:
    """Fetch transaction receipt via RPC"""
    if not RPC_URL:
        print("⚠️  RPC_URL not set", file=sys.stderr)
        return None
    
    try:
        # Ensure tx_hash has 0x prefix
        if not tx_hash.startswith('0x'):
            tx_hash = f'0x{tx_hash}'
        
        payload = {
            "jsonrpc": "2.0",
            "method": "eth_getTransactionReceipt",
            "params": [tx_hash],
            "id": 1
        }
        
        response = requests.post(RPC_URL, json=payload, timeout=15)
        response.raise_for_status()
        
        result = response.json()
        if 'error' in result:
            print(f"⚠️  RPC error for {tx_hash}: {result['error']}", file=sys.stderr)
            return None
        
        return result.get('result')
        
    except Exception as e:
        print(f"⚠️  Error fetching receipt for {tx_hash}: {e}", file=sys.stderr)
        return None

def hex_to_int(hex_value: str) -> int:
    """Convert hex string to integer"""
    if hex_value is None:
        return 0
    return int(hex_value, 16)

def process_batch(tx_hashes: list) -> list:
    """Process a batch of transaction hashes"""
    results = []
    
    for i, tx_hash in enumerate(tx_hashes):
        receipt = fetch_receipt(tx_hash.strip())
        
        if receipt:
            # Extract gas information
            gas_used = hex_to_int(receipt.get('gasUsed', '0x0'))
            effective_gas_price = hex_to_int(receipt.get('effectiveGasPrice', '0x0'))
            
            # For CSV output, remove 0x prefix from tx_hash
            clean_tx_hash = tx_hash.strip()
            if clean_tx_hash.startswith('0x'):
                clean_tx_hash = clean_tx_hash[2:]
            
            results.append({
                'tx_hash': clean_tx_hash,
                'gas_used': gas_used,
                'gas_price': effective_gas_price
            })
        else:
            # Still output a row with zero values for failed fetches
            clean_tx_hash = tx_hash.strip()
            if clean_tx_hash.startswith('0x'):
                clean_tx_hash = clean_tx_hash[2:]
            
            results.append({
                'tx_hash': clean_tx_hash,
                'gas_used': 0,
                'gas_price': 0
            })
        
        if (i + 1) % 10 == 0:
            print(f"   Fetched {i + 1}/{len(tx_hashes)} receipts...", file=sys.stderr)
    
    return results

def main():
    print("🧾 Starting transaction receipt fetching...", file=sys.stderr)
    
    if not RPC_URL:
        print("❌ RPC_URL environment variable not set", file=sys.stderr)
        sys.exit(1)
    
    # Read transaction hashes from stdin
    tx_hashes = []
    for line in sys.stdin:
        line = line.strip()
        if line:
            tx_hashes.append(line)
    
    if not tx_hashes:
        print("⚠️  No transaction hashes provided via stdin", file=sys.stderr)
        # Create empty CSV file
        with open(OUTPUT_FILE, 'w', newline='') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=['tx_hash', 'gas_used', 'gas_price'])
            writer.writeheader()
        print(f"📁 Created empty {OUTPUT_FILE}", file=sys.stderr)
        return
    
    print(f"📥 Processing {len(tx_hashes)} transaction hashes...", file=sys.stderr)
    
    # Write CSV header
    with open(OUTPUT_FILE, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=['tx_hash', 'gas_used', 'gas_price'])
        writer.writeheader()
        
        # Process in batches
        total_processed = 0
        for i in range(0, len(tx_hashes), BATCH_SIZE):
            batch = tx_hashes[i:i + BATCH_SIZE]
            
            print(f"🔄 Processing batch {i//BATCH_SIZE + 1} ({len(batch)} transactions)...", file=sys.stderr)
            
            results = process_batch(batch)
            
            # Write results to CSV
            for row in results:
                writer.writerow(row)
            
            total_processed += len(results)
            
            # Rate limiting
            if len(batch) == BATCH_SIZE and i + BATCH_SIZE < len(tx_hashes):
                print(f"💤 Sleeping {DELAY_BETWEEN_BATCHES}s to respect rate limits...", file=sys.stderr)
                time.sleep(DELAY_BETWEEN_BATCHES)
    
    print(f"✅ Receipt fetching complete! Processed {total_processed} transactions.", file=sys.stderr)
    print(f"📁 Results written to {OUTPUT_FILE}", file=sys.stderr)
    
    # Print summary
    successful_receipts = sum(1 for row in results if row['gas_used'] > 0)
    print(f"📊 Summary: {successful_receipts}/{total_processed} successful receipt fetches", file=sys.stderr)

if __name__ == "__main__":
    main() 