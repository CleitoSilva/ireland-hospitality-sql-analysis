# =============================================================
# PROJECT: Ireland Hospitality Sector SQL Analysis
# FILE:    data/download_cso_data.py
# AUTHOR:  Cleiton Silva
# DATE:    2026
# =============================================================
# DESCRIPTION:
#   Downloads real CSO Ireland data via the PxStat API using
#   the cso-ireland-data Python package.
#   Exports clean CSVs to data/raw/ ready for PostgreSQL import.
#
# HOW TO RUN:
#   1. Open terminal in VS Code (Ctrl + `)
#   2. pip install cso-ireland-data pandas
#   3. python data/download_cso_data.py
#
# DATASETS DOWNLOADED:
#   BRA34 - Business Demography by Activity and County
#   BRA35 - Enterprise Deaths by Activity and Employment Size
#   BRA31 - Business Demography by Activity and Employment Size
# =============================================================

import pandas as pd
import os
import sys
from datetime import datetime

# --- Try to import cso_ireland_data ---
try:
    from cso_ireland_data import CSODataSession
except ImportError:
    print("Package not found. Installing cso-ireland-data...")
    os.system("pip install cso-ireland-data pandas")
    from cso_ireland_data import CSODataSession

# --- Output folder ---
RAW_DIR = os.path.join(os.path.dirname(__file__), "raw")
os.makedirs(RAW_DIR, exist_ok=True)

print("=" * 60)
print("CSO Ireland Data Downloader")
print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print("=" * 60)

cso = CSODataSession()


# =============================================================
# FUNCTION: download and save one CSO table
# =============================================================

def download_table(table_code: str, description: str, output_filename: str) -> pd.DataFrame:
    print(f"\n[{table_code}] {description}")
    print(f"  Downloading from CSO PxStat API...")

    try:
        df = cso.get_table(table_code)
        print(f"  Rows downloaded: {len(df):,}")
        print(f"  Columns: {list(df.columns)}")

        # Save raw version exactly as received
        raw_path = os.path.join(RAW_DIR, output_filename)
        df.to_csv(raw_path, index=False, encoding="utf-8")
        print(f"  Saved to: {raw_path}")
        return df

    except Exception as e:
        print(f"  ERROR downloading {table_code}: {e}")
        return pd.DataFrame()


# =============================================================
# DOWNLOAD 1: BRA34 - Active enterprises by Activity & County
# =============================================================

df_bra34 = download_table(
    table_code      = "BRA34",
    description     = "Business Demography by Activity and County",
    output_filename = "BRA34_activity_county_raw.csv"
)


# =============================================================
# DOWNLOAD 2: BRA35 - Enterprise Deaths by Activity & Size
# =============================================================

df_bra35 = download_table(
    table_code      = "BRA35",
    description     = "Enterprise Deaths by Activity and Employment Size",
    output_filename = "BRA35_enterprise_deaths_raw.csv"
)


# =============================================================
# DOWNLOAD 3: BRA31 - Enterprise Births by Activity & Size
# =============================================================

df_bra31 = download_table(
    table_code      = "BRA31",
    description     = "Business Demography by Activity and Employment Size (Births)",
    output_filename = "BRA31_enterprise_births_raw.csv"
)


# =============================================================
# CLEAN & RESHAPE: standardise column names and filter
# =============================================================

def clean_and_filter(df: pd.DataFrame, table_code: str) -> pd.DataFrame:
    """
    Standardise column names from CSO PxStat format.
    Filter to hospitality-related NACE codes only.
    """
    if df.empty:
        return df

    # Lowercase and strip all column names
    df.columns = [c.strip().lower().replace(" ", "_") for c in df.columns]

    print(f"\n  [{table_code}] Cleaned columns: {list(df.columns)}")

    # Filter to years 2019-2023
    year_col = next((c for c in df.columns if "year" in c or "statistic" in c.lower() or c == "year"), None)
    if year_col:
        df[year_col] = pd.to_numeric(df[year_col], errors="coerce")
        df = df[df[year_col].between(2019, 2023)]
        print(f"  Filtered to 2019-2023: {len(df):,} rows")

    # Replace CSO suppressed values
    df = df.replace({
        "..":  None,
        "N/A": None,
        "-":   None,
        "":    None
    })

    # Filter for hospitality NACE codes where possible
    nace_col = next((c for c in df.columns if "nace" in c or "activity" in c), None)
    if nace_col:
        hospitality_codes = ["I", "I551", "I552", "I553", "I559",
                             "I561", "I562", "I563",
                             "Accommodation", "Food", "Beverage",
                             "Hotel", "Restaurant", "Bar"]
        mask = df[nace_col].astype(str).str.contains(
            "|".join(hospitality_codes), case=False, na=False
        )
        df_hosp = df[mask].copy()
        print(f"  Hospitality rows: {len(df_hosp):,} (of {len(df):,} total)")
        return df_hosp

    return df


# =============================================================
# SAVE CLEANED VERSIONS
# =============================================================

datasets = {
    "BRA34": (df_bra34, "BRA34_activity_county.csv"),
    "BRA35": (df_bra35, "BRA35_enterprise_deaths.csv"),
    "BRA31": (df_bra31, "BRA31_enterprise_births.csv"),
}

print("\n" + "=" * 60)
print("Cleaning and filtering datasets...")
print("=" * 60)

for code, (df, filename) in datasets.items():
    if not df.empty:
        df_clean = clean_and_filter(df, code)
        if not df_clean.empty:
            clean_path = os.path.join(RAW_DIR, filename)
            df_clean.to_csv(clean_path, index=False, encoding="utf-8")
            print(f"  [{code}] Clean file saved: {clean_path}")
        else:
            # If filter returns empty, save full dataset for manual review
            fallback_path = os.path.join(RAW_DIR, filename)
            df.to_csv(fallback_path, index=False, encoding="utf-8")
            print(f"  [{code}] No hospitality rows found — saved full dataset for review: {fallback_path}")


# =============================================================
# INSPECTION: print sample rows from each dataset
# =============================================================

print("\n" + "=" * 60)
print("DATA PREVIEW")
print("=" * 60)

for code, (df, _) in datasets.items():
    if not df.empty:
        print(f"\n--- {code} (first 3 rows) ---")
        print(df.head(3).to_string())


# =============================================================
# SUMMARY REPORT
# =============================================================

print("\n" + "=" * 60)
print("DOWNLOAD SUMMARY")
print("=" * 60)
for code, (df, filename) in datasets.items():
    status = f"{len(df):,} rows" if not df.empty else "FAILED"
    print(f"  {code}: {status}  →  {filename}")

print(f"\nAll files saved to: {RAW_DIR}")
print(f"Finished: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print("=" * 60)
print("\nNEXT STEP:")
print("  Run 01_create_tables.sql in VS Code (SQLTools)")
print("  Then run 02_clean_data.sql to load these CSVs into PostgreSQL")
