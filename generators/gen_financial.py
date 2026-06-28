#!/usr/bin/env python3
"""
gen_financial.py -- fake annual financial / accounting records for a set of
companies. Includes business identifiers SDP recognises (US EIN, bank account
and routing numbers, IBAN) plus a realistic income-statement / balance-sheet.

Outputs:
  financial.csv    -> bucket + BigQuery
  financial.jsonl  -> bucket

Usage: python3 gen_financial.py <out_dir> <size e.g. 10MB>
"""

import csv
import json
import os
import sys

from faker import Faker
from common import parse_size

fake = Faker("en_US")

COLUMNS = [
    "record_id", "company", "ein", "fiscal_year", "currency",
    "revenue", "cost_of_goods_sold", "gross_profit", "operating_expenses",
    "ebitda", "net_income", "total_assets", "total_liabilities",
    "shareholder_equity", "earnings_per_share", "employees",
    "bank_name", "bank_account_number", "routing_number", "iban",
    "cfo_name", "cfo_email",
]


def make_record(i):
    revenue = fake.pyint(min_value=1_000_000, max_value=5_000_000_000)
    cogs = int(revenue * fake.pyfloat(min_value=0.3, max_value=0.7))
    gross = revenue - cogs
    opex = int(gross * fake.pyfloat(min_value=0.3, max_value=0.8))
    ebitda = gross - opex
    net = int(ebitda * fake.pyfloat(min_value=0.4, max_value=0.9))
    assets = fake.pyint(min_value=revenue, max_value=revenue * 3)
    liabilities = int(assets * fake.pyfloat(min_value=0.2, max_value=0.7))
    return {
        "record_id": i,
        "company": fake.company(),
        "ein": fake.numerify("##-#######"),          # US Employer ID Number
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
        "shareholder_equity": assets - liabilities,
        "earnings_per_share": round(fake.pyfloat(min_value=0.1, max_value=25.0), 2),
        "employees": fake.pyint(min_value=10, max_value=250000),
        "bank_name": fake.company() + " Bank",
        "bank_account_number": fake.numerify("##########"),
        "routing_number": fake.aba(),                # ABA routing transit number
        "iban": fake.iban(),
        "cfo_name": fake.name(),
        "cfo_email": fake.ascii_company_email(),
    }


def main(out_dir, size):
    target = parse_size(size)
    os.makedirs(out_dir, exist_ok=True)
    csv_path = os.path.join(out_dir, "financial.csv")
    jsonl_path = os.path.join(out_dir, "financial.jsonl")

    csv_f = open(csv_path, "w", newline="", encoding="utf-8")
    json_f = open(jsonl_path, "w", encoding="utf-8")
    writer = csv.DictWriter(csv_f, fieldnames=COLUMNS)
    writer.writeheader()

    rows = 0
    i = 1
    while True:
        rec = make_record(i)
        writer.writerow(rec)
        json_f.write(json.dumps(rec, default=str) + "\n")
        rows += 1
        i += 1
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
