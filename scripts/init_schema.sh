#!/bin/bash
# Schema initialization script for UniChain WBTC/ETH swap fact pipeline
# Runs all DDL files to set up the database structure

set -e  # Exit on any error

echo "🚀 Initializing database schema for UniChain WBTC/ETH swap fact pipeline..."

# Database connection parameters
DB_HOST=${PGHOST:-postgres}
DB_PORT=${PGPORT:-5432}
DB_NAME=${PGDATABASE:-postgres}
DB_USER=${PGUSER:-postgres}

# Wait for database to be ready
echo "⏳ Waiting for PostgreSQL to be ready..."
until pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER"; do
    echo "Waiting for postgres..."
    sleep 2
done

echo "✅ PostgreSQL is ready!"

# Run DDL files in order
echo "📋 Creating raw swaps tables..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f sql/ddl/00_raw_swaps.sql

echo "📊 Creating fact table..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f sql/ddl/01_fact_table.sql

echo "💰 Creating token pricing view..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f sql/views/token_prices_usd_day.sql

echo "🎉 Schema initialization complete!"

# Print table counts for verification
echo "📈 Current table statistics:"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT 
    schemaname,
    tablename,
    n_tup_ins as inserted_rows,
    n_tup_upd as updated_rows,
    n_tup_del as deleted_rows
FROM pg_stat_user_tables 
WHERE schemaname IN ('public', 'labs_solo')
ORDER BY schemaname, tablename;
"

echo "✨ Ready for HyperIndex to start populating raw_unichain_swaps!" 