#!/usr/bin/env python3
"""
Welcome to gen_financial.py!
This script creates fake financial reports for fake companies.
It includes:
- Company names.
- US EINs (Employer Identification Numbers, like a social security number for a business).
- Fake bank account numbers and routing numbers.
- Fake financial numbers (Revenue, Expenses, Profit) that actually make math sense!
  (e.g., Gross Profit = Revenue - Cost of Goods Sold).

We use this to test if our security tools can find corporate financial secrets
and business identifiers.
"""

import csv
import json
import os
import sys

# We import 'Faker' to make fake company names and numbers.
from faker import Faker
# We import our 'parse_size' tool.
from common import parse_size

# Initialize the Faker tool.
fake = Faker("en_US")

# These are the columns we will save in our spreadsheet.
COLUMNS = [
    "record_id", "company", "ein", "fiscal_year", "currency",
    "revenue", "cost_of_goods_sold", "gross_profit", "operating_expenses",
    "ebitda", "net_income", "total_assets", "total_liabilities",
    "shareholder_equity", "earnings_per_share", "employees",
    "bank_name", "bank_account_number", "routing_number", "iban",
    "cfo_name", "cfo_email",
]


def make_record(i):
    """
    This function makes one fake financial record.
    It does some basic math so the numbers look realistic.
    """
    # 1. Pick a random revenue between 1 million and 5 billion.
    revenue = fake.pyint(min_value=1_000_000, max_value=5_000_000_000)
    
    # 2. Cost of Goods Sold (COGS) is usually 30% to 70% of revenue.
    cogs = int(revenue * fake.pyfloat(min_value=0.3, max_value=0.7))
    
    # 3. Gross Profit is what is left after COGS.
    gross = revenue - cogs
    
    # 4. Operating Expenses (Opex) is 30% to 80% of gross profit.
    opex = int(gross * fake.pyfloat(min_value=0.3, max_value=0.8))
    
    # 5. EBITDA (Earnings Before Interest, Taxes, Depreciation, and Amortization)
    # is Gross Profit minus Opex.
    ebitda = gross - opex
    
    # 6. Net Income (final profit) is 40% to 90% of EBITDA (after taxes/interest).
    net = int(ebitda * fake.pyfloat(min_value=0.4, max_value=0.9))
    
    # 7. Assets are usually 1 to 3 times the revenue.
    assets = fake.pyint(min_value=revenue, max_value=revenue * 3)
    
    # 8. Liabilities (debts) are 20% to 70% of assets.
    liabilities = int(assets * fake.pyfloat(min_value=0.2, max_value=0.7))
    
    return {
        "record_id": i,
        "company": fake.company(),
        # EIN is formatted as XX-XXXXXXX.
        "ein": fake.numerify("##-#######"),          
        "fiscal_year": fake.pyint(min_value=2015, max_value=2025),
        "currency": "USD",
        "revenue": revenue,
        "cost_of_goods_sold": cogs,
        "gross_profit": gross,
        "operating_expenses": opex,
        "ebitda": ebitda,
        "net_income": net,
        "total_assets": assets,
        "total_liabilities": liabilities,
        # Shareholder Equity is Assets minus Liabilities.
        "shareholder_equity": assets - liabilities,
        "earnings_per_share": round(fake.pyfloat(min_value=0.1, max_value=25.0), 2),
        "employees": fake.pyint(min_value=10, max_value=250000),
        "bank_name": fake.company() + " Bank",
        "bank_account_number": fake.numerify("##########"),
        "routing_number": fake.aba(),                # ABA routing number (for bank wires)
        "iban": fake.iban(),                         # International bank account number
        "cfo_name": fake.name(),                     # Chief Financial Officer name
        "cfo_email": fake.ascii_company_email(),
    }


def main(out_dir, size):
    # Convert size to bytes.
    target = parse_size(size)
    os.makedirs(out_dir, exist_ok=True)
    
    csv_path = os.path.join(out_dir, "financial.csv")
    jsonl_path = os.path.join(out_dir, "financial.jsonl")

    # Open files for writing.
    csv_f = open(csv_path, "w", newline="", encoding="utf-8")
    json_f = open(jsonl_path, "w", encoding="utf-8")
    
    writer = csv.DictWriter(csv_f, fieldnames=COLUMNS)
    writer.writeheader()

    rows = 0
    i = 1
    # Keep writing until we hit the target size.
    while True:
        rec = make_record(i)
        writer.writerow(rec)
        json_f.write(json.dumps(rec, default=str) + "\n")
        rows += 1
        i += 1
        
        # Check size every 200 rows.
        if rows % 200 == 0:
            csv_f.flush()
            if os.path.getsize(csv_path) >= target:
                break

    csv_f.close()
    json_f.close()
    print("financial: wrote %d records (%.1f MB) to %s"
          % (rows, os.path.getsize(csv_path) / 1e6, out_dir))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
