#!/usr/bin/env python3
"""
gen_patents.py -- fake intellectual-property / patent filings. Each filing
reads like a real patent application (title, inventors with addresses,
assignee, abstract, claims) so SDP sees document-style sensitive content plus
inventor PII. Also emits a flat CSV summary for BigQuery.

Outputs:
  patents.jsonl            -> bucket (one JSON object per filing)
  patents.csv              -> bucket + BigQuery (flat summary, no claims body)
  docs/patent_<n>.txt      -> bucket (individual document files, realistic)

Usage: python3 gen_patents.py <out_dir> <size e.g. 10MB>
"""

import csv
import json
import os
import sys

from faker import Faker
from common import parse_size

fake = Faker("en_US")

CSV_COLUMNS = [
    "application_number", "title", "assignee", "filing_date",
    "classification", "lead_inventor", "lead_inventor_email", "num_claims",
]

_FIELDS = ["apparatus", "method", "system", "composition", "process"]
_DOMAINS = ["machine learning", "battery chemistry", "wireless networking",
            "gene editing", "image compression", "autonomous navigation",
            "semiconductor fabrication", "renewable energy storage"]


def make_record(i):
    inventors = []
    for _ in range(fake.pyint(min_value=1, max_value=4)):
        inventors.append({
            "name": fake.name(),
            "address": fake.address().replace("\n", ", "),
            "email": fake.ascii_email(),
        })
    domain = fake.random_element(_DOMAINS)
    kind = fake.random_element(_FIELDS)
    n_claims = fake.pyint(min_value=8, max_value=20)
    claims = []
    for c in range(1, n_claims + 1):
        claims.append("%d. A %s for %s, comprising: %s"
                      % (c, kind, domain, fake.paragraph(nb_sentences=3)))
    return {
        "application_number": fake.numerify("US ##/###,###"),
        "title": ("%s for %s using %s" % (kind.title(), domain, fake.bs())),
        "assignee": fake.company(),
        "filing_date": fake.date_between(start_date="-10y").isoformat(),
        "classification": fake.lexify("?##?/##").upper(),   # fake CPC-ish code
        "inventors": inventors,
        "abstract": fake.paragraph(nb_sentences=6),
        "claims": claims,
    }


def main(out_dir, size):
    target = parse_size(size)
    os.makedirs(out_dir, exist_ok=True)
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
        json_f.write(json.dumps(rec, default=str) + "\n")
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
        # Write a realistic standalone document file too.
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
