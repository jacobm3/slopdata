# Synthetic Sensitive-Data Generator for GCP SDP / SCC demos

Generate realistic-but-**fake** sensitive data, load it into typical GCP
storage services, and let **Sensitive Data Protection (SDP)** and **Security
Command Center (SCC)** discover and classify it — for demos, training, and
testing detection coverage.

Everything is fake. The credit cards authenticate to nothing, the patients
don't exist, the API keys unlock nothing. The data only *looks* real enough
for SDP's infotype detectors to fire.

---

## What it creates

**Data types** (each independently toggled and sized):

| Type | Tool | What's in it (SDP infotypes it triggers) |
|------|------|------------------------------------------|
| Customer records | [Faker](https://faker.readthedocs.io/) | Names, emails, phones, **SSNs**, addresses, DOB, **full credit-card PANs**, plus **PCI-DSS violations**: CVV, PIN, and full magnetic-stripe track data. IBANs. |
| Medical patients | [Synthea](https://github.com/synthetichealth/synthea) (MITRE) | Realistic patient CSVs: names, SSNs, addresses, conditions, medications, encounters. |
| Patent filings | Faker + templates | IP / patent applications: titles, abstracts, claims, **inventor PII** (names, addresses, emails), assignees. |
| Financial records | Faker | Annual income statements / balance sheets, **EINs**, bank account + **routing numbers**, IBANs, CFO PII. |
| Leaked secrets | Faker + format templates | **GCP API keys, GCP service-account JSON keys, AWS keys, JWTs, RSA private keys, passwords, DB connection strings** — the "credentials in a bucket" finding. |

**GCP resources** (all named with your chosen prefix):

- **Cloud Storage** bucket — every data type, in per-type folders. Uniform
  bucket-level access, public-access-prevention **enforced**, objects
  auto-deleted after N days.
- **BigQuery** dataset + tables — customers, financial, patents, and the
  key medical tables, loaded from the bucket.
- **Cloud SQL (PostgreSQL)** — smallest tier (`db-f1-micro`), customer data
  imported server-side from the bucket. *(Optional — the only real recurring
  cost.)*

These are exactly the sources SDP discovery supports (Cloud Storage,
BigQuery, Cloud SQL), so all three light up in SCC.

---

## Quick start (GCP Cloud Shell)

```bash
git clone https://github.com/jacobm3/slopdata.git
cd slopdata

# 1. set your prefix (and optionally project/region/volumes)
nano config.env          # at minimum set PREFIX

# 2. run it — generates data, shows a plan, asks before creating anything
./bootstrap.sh
```

That's the whole flow. Cloud Shell already has `gcloud`, `bq`, `gsutil`,
`terraform`, `python3`, and `java` installed, and you're already
authenticated, so there's nothing else to set up.

When it finishes it prints the bucket / dataset / instance names and how to
turn on SDP discovery.

### Tear down (stop all cost)

```bash
./destroy.sh
```

---

## Configuration

All settings live in **`config.env`** — it's commented; edit and re-run.

| Setting | Default | Notes |
|---------|---------|-------|
| `PREFIX` | `sdp-demo` | Goes in front of every resource name. |
| `PROJECT_ID` | *(active gcloud project)* | Where to deploy. |
| `REGION` | `us-central1` | Cheapest broad-support region. |
| `ENABLE_*` | all `true` | Turn individual data types on/off. |
| `VOL_*` | `10MB` (`10KB` for secrets) | Per-type data volume. |
| `ENABLE_CLOUDSQL` | `true` | The managed database. |
| `RETENTION_DAYS` | `7` | Bucket objects auto-delete after this. `0` = never. |

### Data volume

Each `VOL_*` accepts sizes like `10KB`, `100KB`, `1MB`, `10MB`, `100MB`,
`1GB`, `10GB` (KB/MB/GB are 1000-based). Structured generators write rows
until the file hits the target. Medical volume maps to a Synthea patient
count (≈80 KB of CSV per patient — approximate, not byte-exact).

Bigger volumes mean more SDP findings but more generation time, storage, and
(for the database) import time. **10 MB is plenty for a discovery demo.**

---

## Cost

Defaults are tuned to be cheap:

- **Buckets + BigQuery only** (`ENABLE_CLOUDSQL=false`): effectively free at
  rest — a few MB of Standard storage and tiny BigQuery tables (pennies),
  and the bucket auto-empties after `RETENTION_DAYS`.
- **With Cloud SQL** (default): `db-f1-micro`, 10 GB HDD, no HA, no backups —
  roughly **$8–10/month** while it runs. This is the only meaningful
  recurring cost. Run `./destroy.sh` when the demo's done, or set
  `ENABLE_CLOUDSQL=false`.

No NAT gateways, load balancers, or other surprise line items are created.

---

## Security

The Terraform is written to **add no new exposure**:

- **Bucket:** uniform bucket-level access, `public_access_prevention =
  enforced`, no `allUsers`/`allAuthenticatedUsers` IAM. Not public.
- **Cloud SQL:** **zero authorized networks** and SSL required, so no client
  on any network can connect. Customer data is loaded **server-side** via
  `gcloud sql import` reading from the bucket — nothing is sent over a
  database connection. Deletion protection is off so the demo can be cleanly
  destroyed.
- **IAM:** the only binding created is read-only (`storage.objectViewer`) for
  the Cloud SQL service account on *our own* bucket, so import works.
- No new VPCs, firewall rules, public IPs that accept traffic, or service
  account keys are created. The whole thing runs as *your* Cloud Shell
  identity.

The generated data is intentionally "sensitive-looking" — keep the bucket and
dataset private (they are by default) and tear them down when finished.

---

## Turning on SDP discovery

After `bootstrap.sh` finishes:

1. Console → **Security → Sensitive Data Protection → Discovery**.
2. Create scan configurations for **Cloud Storage**, **BigQuery**, and (if
   enabled) **Cloud SQL**, scoped to this project.
3. Data profiles appear within minutes-to-hours and surface in **Security
   Command Center** as findings.

---

## Layout

```
config.env            # all your settings
bootstrap.sh          # the one command: generate + deploy + load
destroy.sh            # tear everything down
generators/
  common.py           # size parsing + helpers (run it for a self-check)
  gen_customers.py    # PII + credit cards (+ PCI-violating fields)
  gen_financial.py    # annual financial records
  gen_patents.py      # IP / patent filings
  gen_secrets.py      # leaked credentials
  run_synthea.sh      # downloads + runs Synthea for medical data
  requirements.txt    # just Faker
terraform/            # bucket + BigQuery + Cloud SQL (infra only)
```

Data generation and infra are separate: Terraform builds empty infrastructure;
`bootstrap.sh` generates the data and loads it. That keeps the Terraform clean
and lets you regenerate data without touching infra.

---

## Notes / limitations

- All data is synthetic. Do not treat any value as a real secret or identity.
- Medical sizing is approximate (patient-count based).
- Cloud SQL discovery support in SDP is newer than Storage/BigQuery; if you
  don't need a database in the demo, set `ENABLE_CLOUDSQL=false` for the
  cheapest, simplest run.
