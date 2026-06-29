#!/usr/bin/env python3
"""
gen_customers.py -- fake customer records with PII and credit-card data,
including fields that REAL systems must never store (PCI-DSS violations:
full CVV, PIN, and magnetic-stripe track data). That is the point here: it
gives GCP Sensitive Data Protection plenty of high-severity stuff to find.

Outputs three files into the given output dir (same records in each):
  customers.csv    -> uploaded to the bucket AND loaded into BigQuery
  customers.jsonl  -> uploaded to the bucket (semi-structured example)
  customers.sql    -> imported into Cloud SQL (Postgres) server-side from GCS

Usage: python3 gen_customers.py <out_dir> <size e.g. 10MB>
"""

import csv
import io
import json
import os
import sys

from faker import Faker
from common import parse_size

fake = Faker("en_US")

# Columns, in order. Mix of standard PII and deliberately-non-compliant fields.
COLUMNS = [
    "customer_id", "first_name", "last_name", "email", "phone",
    "ssn", "date_of_birth", "street", "city", "state", "zip", "country",
    "credit_card_type", "credit_card_number", "credit_card_expiry",
    "cvv",                  # PCI violation: never store the CVV
    "card_pin",             # PCI violation: never store the PIN
    "magstripe_track_data", # PCI violation: never store full track data
    "iban", "account_balance",
]


def make_record(i):
    """Build one fake customer as a dict."""
    first = fake.first_name()
    last = fake.last_name()
    pan = fake.credit_card_number()           # Luhn-valid fake PAN
    exp = fake.credit_card_expire()           # MM/YY
    # Build plausible-looking magnetic-stripe track 1 + track 2 data.
    yymm = exp[3:5] + exp[0:2]
    track1 = "%%B%s^%s/%s^%s1010000?" % (pan, last.upper(), first.upper(), yymm)
    track2 = ";%s=%s1010000?" % (pan, yymm)
    return {
        "customer_id": i,
        "first_name": first,
        "last_name": last,
        "email": fake.ascii_email(),
        "phone": fake.phone_number(),
        "ssn": fake.ssn(),
        "date_of_birth": fake.date_of_birth(minimum_age=18, maximum_age=90).isoformat(),
        "street": fake.street_address(),
        "city": fake.city(),
        "state": fake.state_abbr(),
        "zip": fake.zipcode(),
        "country": "US",
        "credit_card_type": fake.credit_card_provider(),
        "credit_card_number": pan,
        "credit_card_expiry": exp,
        "cvv": fake.credit_card_security_code(),
        "card_pin": fake.numerify("####"),
        "magstripe_track_data": track1 + " " + track2,
        "iban": fake.iban(),
        "account_balance": fake.pydecimal(left_digits=6, right_digits=2, positive=True),
    }


def sql_value(v):
    """Render a Python value as a Postgres SQL literal."""
    if isinstance(v, (int, float)):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"   # escape single quotes


def main(out_dir, size):
    target = parse_size(size)
    os.makedirs(out_dir, exist_ok=True)
    csv_path = os.path.join(out_dir, "customers.csv")
    jsonl_path = os.path.join(out_dir, "customers.jsonl")
    sql_path = os.path.join(out_dir, "customers.sql")

    # CREATE TABLE for the Cloud SQL import (all text/numeric, keep it simple).
    cols_ddl = ",\n  ".join(
        ("account_balance NUMERIC" if c == "account_balance"
         else ("customer_id BIGINT PRIMARY KEY" if c == "customer_id"
               else c + " TEXT"))
        for c in COLUMNS
    )
    ddl = ("DROP TABLE IF EXISTS customers;\n"
           "CREATE TABLE customers (\n  %s\n);\n"
           "DO $$\n"
           "BEGIN\n"
           "  IF EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'sdp_readonly') THEN\n"
           "    GRANT USAGE ON SCHEMA public TO sdp_readonly;\n"
           "    GRANT SELECT ON ALL TABLES IN SCHEMA public TO sdp_readonly;\n"
           "    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO sdp_readonly;\n"
           "  END IF;\n"
           "END\n"
           "$$;\n" % cols_ddl)

    csv_f = open(csv_path, "w", newline="", encoding="utf-8")
    json_f = open(jsonl_path, "w", encoding="utf-8")
    sql_f = open(sql_path, "w", encoding="utf-8")
    writer = csv.DictWriter(csv_f, fieldnames=COLUMNS)
    writer.writeheader()
    sql_f.write(ddl)

    rows = 0
    i = 1
    # We size against the CSV file (the canonical one); the other two files
    # have the same record count.
    while True:
        rec = make_record(i)
        writer.writerow(rec)
        json_f.write(json.dumps(rec, default=str) + "\n")
        vals = ", ".join(sql_value(rec[c]) for c in COLUMNS)
        sql_f.write("INSERT INTO customers VALUES (%s);\n" % vals)
        rows += 1
        i += 1
        if rows % 200 == 0:
            csv_f.flush()
            if os.path.getsize(csv_path) >= target:
                break

    csv_f.close()
    json_f.close()
    sql_f.close()
    print("customers: wrote %d records (%.1f MB) to %s"
          % (rows, os.path.getsize(csv_path) / 1e6, out_dir))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
