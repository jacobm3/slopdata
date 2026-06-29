#!/usr/bin/env python3
"""
Welcome to gen_customers.py!
This script creates fake customer records.
To make it interesting, it includes "PII" (Personally Identifiable Information)
like names, Social Security Numbers (SSN), and birthdays.

It also deliberately includes bad things that real companies should NEVER store:
- Credit Card CVV numbers (the 3-digit code on the back).
- Card PINs (your secret password for the ATM).
- Magnetic stripe data (the secret stuff on the back of the card).

Storing these is a big no-no (called a PCI-DSS violation). We put them here
on purpose so that Google Cloud's security tools have something juicy to find!

It creates three files with the same fake customers:
1. customers.csv  (like a spreadsheet)
2. customers.jsonl (a format programmers like)
3. customers.sql   (instructions to load the data into a SQL database)
"""

import csv
import io
import json
import os
import sys

# We import 'Faker', which is a library that generates fake names/addresses.
from faker import Faker
# We import our 'parse_size' tool from our 'common.py' file.
from common import parse_size

# Initialize the Faker tool. "en_US" means make American-sounding names.
fake = Faker("en_US")

# This is the list of columns (fields) we want for each customer.
COLUMNS = [
    "customer_id", "first_name", "last_name", "email", "phone",
    "ssn", "date_of_birth", "street", "city", "state", "zip", "country",
    "credit_card_type", "credit_card_number", "credit_card_expiry",
    "cvv",                  # Bad! Never store this.
    "card_pin",             # Bad! Never store this.
    "magstripe_track_data", # Bad! Never store this.
    "iban", "account_balance",
]


def make_record(i):
    """
    This function creates ONE fake customer.
    It returns a dictionary (a set of key-value pairs).
    """
    first = fake.first_name()
    last = fake.last_name()
    pan = fake.credit_card_number()           # A fake but realistic credit card number.
    exp = fake.credit_card_expire()           # Expiry date (MM/YY).
    
    # We build fake "magnetic stripe" data.
    # If you swipe a card, the machine reads this text.
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
        # Make sure they are between 18 and 90 years old.
        "date_of_birth": fake.date_of_birth(minimum_age=18, maximum_age=90).isoformat(),
        "street": fake.street_address(),
        "city": fake.city(),
        "state": fake.state_abbr(),
        "zip": fake.zipcode(),
        "country": "US",
        "credit_card_type": fake.credit_card_provider(),
        "credit_card_number": pan,
        "credit_card_expiry": exp,
        "cvv": fake.credit_card_security_code(), # 3-digit code
        "card_pin": fake.numerify("####"),       # 4-digit PIN
        "magstripe_track_data": track1 + " " + track2,
        "iban": fake.iban(),                     # International bank account number
        "account_balance": fake.pydecimal(left_digits=6, right_digits=2, positive=True),
    }


def sql_value(v):
    """
    This helper converts a Python value into something SQL understands.
    For example:
      - Numbers (like 123) stay as numbers.
      - Text (like 'Alice') becomes 'Alice' (with single quotes).
      - If the text has a quote in it (like "O'Connor"), we double it ("O''Connor")
        so SQL doesn't get confused.
    """
    if isinstance(v, (int, float)):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


def main(out_dir, size):
    # Convert the size (e.g. "10MB") into a number of bytes.
    target = parse_size(size)
    
    # Make sure the output folder exists.
    os.makedirs(out_dir, exist_ok=True)
    
    # Define the paths for the three files we will create.
    csv_path = os.path.join(out_dir, "customers.csv")
    jsonl_path = os.path.join(out_dir, "customers.jsonl")
    sql_path = os.path.join(out_dir, "customers.sql")

    # We generate the SQL DDL (Data Definition Language).
    # This is the SQL code that creates the database table.
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

    # Open all three files for writing.
    csv_f = open(csv_path, "w", newline="", encoding="utf-8")
    json_f = open(jsonl_path, "w", encoding="utf-8")
    sql_f = open(sql_path, "w", encoding="utf-8")
    
    # Set up the CSV writer (helps us write neat CSV rows).
    writer = csv.DictWriter(csv_f, fieldnames=COLUMNS)
    writer.writeheader()
    
    # Write the table creation SQL code to the SQL file.
    sql_f.write(ddl)

    rows = 0
    i = 1
    
    # Keep generating customers until the CSV file is big enough.
    while True:
        # 1. Make a fake customer.
        rec = make_record(i)
        
        # 2. Write to CSV.
        writer.writerow(rec)
        
        # 3. Write to JSONL (JSON Lines: one JSON object per line).
        json_f.write(json.dumps(rec, default=str) + "\n")
        
        # 4. Write to SQL (as an INSERT statement).
        vals = ", ".join(sql_value(rec[c]) for c in COLUMNS)
        sql_f.write("INSERT INTO customers VALUES (%s);\n" % vals)
        
        rows += 1
        i += 1
        
        # Every 200 rows, check if we hit the target size.
        if rows % 200 == 0:
            csv_f.flush()
            if os.path.getsize(csv_path) >= target:
                break

    # Close all the files.
    csv_f.close()
    json_f.close()
    sql_f.close()
    
    # Tell the user how we did.
    print("customers: wrote %d records (%.1f MB) to %s"
          % (rows, os.path.getsize(csv_path) / 1e6, out_dir))


if __name__ == "__main__":
    # Run the main function with the arguments passed from the command line.
    # sys.argv[1] is the output directory.
    # sys.argv[2] is the size.
    main(sys.argv[1], sys.argv[2])
