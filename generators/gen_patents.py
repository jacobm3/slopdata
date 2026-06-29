#!/usr/bin/env python3
"""
Welcome to gen_patents.py!
This script creates fake patent applications.
A patent is a document that describes a new invention so other people
can't copy it.

Each fake patent includes:
- An application number.
- A title (e.g., "Method for Machine Learning using Synergistic Blockchains").
- The company that owns it (Assignee).
- The inventors' names, addresses, and emails.
- An abstract (a short summary of the invention).
- Claims (the specific parts of the invention being protected).

We write these as:
1. A JSONL file (for easy computer reading).
2. A CSV file (a flat summary).
3. Individual text files in a "docs" folder that look like real patent papers.

This helps us test if security tools can find sensitive information hidden
inside unstructured text documents (like word files or PDFs).
"""

import csv
import json
import os
import sys

from faker import Faker
from common import parse_size

fake = Faker("en_US")

# Columns for the summary CSV file.
CSV_COLUMNS = [
    "application_number", "title", "assignee", "filing_date",
    "classification", "lead_inventor", "lead_inventor_email", "num_claims",
]

# Some fake words to build funny invention names.
_FIELDS = ["apparatus", "method", "system", "composition", "process"]
_DOMAINS = ["machine learning", "battery chemistry", "wireless networking",
            "gene editing", "image compression", "autonomous navigation",
            "semiconductor fabrication", "renewable energy storage"]


def make_record(i):
    """
    This function builds one fake patent.
    It generates a list of inventors, a title, and some fake "claims".
    """
    # Generate 1 to 4 inventors.
    inventors = []
    for _ in range(fake.pyint(min_value=1, max_value=4)):
        inventors.append({
            "name": fake.name(),
            # Replace newlines with commas to keep the address on one line.
            "address": fake.address().replace("\n", ", "),
            "email": fake.ascii_email(),
        })
        
    # Pick a random domain and type of invention.
    domain = fake.random_element(_DOMAINS)
    kind = fake.random_element(_FIELDS)
    
    # Decide how many "claims" this patent has.
    n_claims = fake.pyint(min_value=8, max_value=20)
    claims = []
    for c in range(1, n_claims + 1):
        # Build a fake claim sentence.
        claims.append("%d. A %s for %s, comprising: %s"
                      % (c, kind, domain, fake.paragraph(nb_sentences=3)))
                      
    return {
        "application_number": fake.numerify("US ##/###,###"),
        "title": ("%s for %s using %s" % (kind.title(), domain, fake.bs())),
        "assignee": fake.company(),
        "filing_date": fake.date_between(start_date="-10y").isoformat(),
        "classification": fake.lexify("?##?/##").upper(),   # e.g., "A01B/12"
        "inventors": inventors,
        "abstract": fake.paragraph(nb_sentences=6),
        "claims": claims,
    }


def main(out_dir, size):
    target = parse_size(size)
    os.makedirs(out_dir, exist_ok=True)
    
    # Create a subfolder called "docs" for the text files.
    docs_dir = os.path.join(out_dir, "docs")
    os.makedirs(docs_dir, exist_ok=True)
    
    jsonl_path = os.path.join(out_dir, "patents.jsonl")
    csv_path = os.path.join(out_dir, "patents.csv")

    json_f = open(jsonl_path, "w", encoding="utf-8")
    csv_f = open(csv_path, "w", newline="", encoding="utf-8")
    
    writer = csv.DictWriter(csv_f, fieldnames=CSV_COLUMNS)
    writer.writeheader()

    rows = 0
    i = 1
    while True:
        rec = make_record(i)
        
        # Write to the JSONL file.
        json_f.write(json.dumps(rec, default=str) + "\n")
        
        # Write a summary row to the CSV.
        writer.writerow({
            "application_number": rec["application_number"],
            "title": rec["title"],
            "assignee": rec["assignee"],
            "filing_date": rec["filing_date"],
            "classification": rec["classification"],
            "lead_inventor": rec["inventors"][0]["name"],
            "lead_inventor_email": rec["inventors"][0]["email"],
            "num_claims": len(rec["claims"]),
        })
        
        # Write a realistic standalone text document.
        # This looks like a real patent application printout.
        with open(os.path.join(docs_dir, "patent_%d.txt" % i), "w",
                  encoding="utf-8") as d:
            d.write("UNITED STATES PATENT APPLICATION\n")
            d.write("Application No.: %s\n" % rec["application_number"])
            d.write("Title: %s\n" % rec["title"])
            d.write("Assignee: %s\n\n" % rec["assignee"])
            d.write("Inventors:\n")
            for inv in rec["inventors"]:
                d.write("  - %s, %s <%s>\n"
                        % (inv["name"], inv["address"], inv["email"]))
            d.write("\nABSTRACT\n%s\n\nCLAIMS\n" % rec["abstract"])
            d.write("\n".join(rec["claims"]) + "\n")

        rows += 1
        i += 1
        # Check size every 50 rows (patents are large documents).
        if rows % 50 == 0:
            json_f.flush()
            if os.path.getsize(jsonl_path) >= target:
                break

    json_f.close()
    csv_f.close()
    print("patents: wrote %d filings (%.1f MB) to %s"
          % (rows, os.path.getsize(jsonl_path) / 1e6, out_dir))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
