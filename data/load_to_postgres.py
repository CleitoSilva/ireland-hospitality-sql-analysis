# =============================================================
# PROJECT: Ireland Hospitality Sector SQL Analysis
# FILE:    data/load_to_postgres.py
# AUTHOR:  Cleiton Silva
# DATE:    2026
# =============================================================
# DESCRIPTION:
#   Loads the cleaned CSVs from data/raw/ directly into
#   PostgreSQL staging tables using psycopg2 + pandas.
#   Run AFTER download_cso_data.py.
#
# HOW TO RUN:
#   1. Open terminal in VS Code (Ctrl + `)
#   2. pip install psycopg2-binary pandas
#   3. Update DB_CONFIG below with your PostgreSQL password
#   4. python data/load_to_postgres.py
# =============================================================

import pandas as pd
import psycopg2
from psycopg2.extras import execute_values
import os
import sys

# =============================================================
# DATABASE CONFIG — update your password here
# =============================================================

DB_CONFIG = {
    "host":     "localhost",
    "port":     5432,
    "dbname":   "postgres",
    "user":     "postgres",
    "password": "YOUR_PASSWORD_HERE"   # <-- change this
}

RAW_DIR = os.path.join(os.path.dirname(__file__), "raw")


# =============================================================
# CONNECT
# =============================================================

def get_connection():
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        print("Connected to PostgreSQL successfully.")
        return conn
    except psycopg2.OperationalError as e:
        print(f"Connection failed: {e}")
        print("Check your password in DB_CONFIG and that PostgreSQL is running.")
        sys.exit(1)


# =============================================================
# LOAD CSV INTO STAGING TABLE
# =============================================================

def load_csv_to_staging(conn, csv_path: str, staging_table: str, columns: list):
    """
    Reads a CSV and bulk-inserts it into a staging table.
    All values are treated as text at this stage.
    """
    if not os.path.exists(csv_path):
        print(f"  File not found: {csv_path} — skipping.")
        return 0

    df = pd.read_csv(csv_path, dtype=str, encoding="utf-8")
    df = df.fillna("")   # replace NaN with empty string for text columns

    print(f"\n  Loading {os.path.basename(csv_path)}")
    print(f"  Rows: {len(df):,}  |  Columns: {list(df.columns)}")

    # Map CSV columns to staging columns — use positional if names differ
    if len(df.columns) >= len(columns):
        df_subset = df.iloc[:, :len(columns)].copy()
        df_subset.columns = columns
    else:
        print(f"  WARNING: CSV has {len(df.columns)} cols, expected {len(columns)}. Check manually.")
        return 0

    rows = [tuple(row) for row in df_subset.itertuples(index=False)]

    with conn.cursor() as cur:
        # Clear staging first (idempotent)
        cur.execute(f"TRUNCATE TABLE hospitality.{staging_table}")

        col_str = ", ".join(columns)
        execute_values(
            cur,
            f"INSERT INTO hospitality.{staging_table} ({col_str}) VALUES %s",
            rows,
            page_size=500
        )
        conn.commit()

    print(f"  Inserted {len(rows):,} rows into hospitality.{staging_table}")
    return len(rows)


# =============================================================
# MAIN
# =============================================================

def main():
    print("=" * 60)
    print("PostgreSQL Loader — Ireland Hospitality Project")
    print("=" * 60)

    conn = get_connection()

    # Define CSV → staging table mappings
    # Columns must match the staging table definitions in 02_clean_data.sql
    loads = [
        {
            "csv":     os.path.join(RAW_DIR, "BRA34_activity_county.csv"),
            "table":   "staging_enterprise_activity",
            "columns": ["raw_year", "raw_county", "raw_sector",
                        "raw_nace_code", "raw_size_class",
                        "raw_active", "raw_persons"]
        },
        {
            "csv":     os.path.join(RAW_DIR, "BRA35_enterprise_deaths.csv"),
            "table":   "staging_enterprise_deaths",
            "columns": ["raw_year", "raw_county", "raw_sector",
                        "raw_nace_code", "raw_size_class",
                        "raw_ceased", "raw_persons"]
        },
        {
            "csv":     os.path.join(RAW_DIR, "BRA31_enterprise_births.csv"),
            "table":   "staging_enterprise_births",
            "columns": ["raw_year", "raw_county", "raw_sector",
                        "raw_nace_code", "raw_size_class",
                        "raw_new", "raw_persons"]
        },
    ]

    total_rows = 0
    for item in loads:
        rows = load_csv_to_staging(conn, item["csv"], item["table"], item["columns"])
        total_rows += rows

    conn.close()

    print("\n" + "=" * 60)
    print(f"Total rows loaded into staging: {total_rows:,}")
    print("=" * 60)
    print("\nNEXT STEP:")
    print("  Open 02_clean_data.sql in VS Code")
    print("  Run Steps 3-6 to clean staging and load into production tables")


if __name__ == "__main__":
    main()
