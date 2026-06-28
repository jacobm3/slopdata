#!/usr/bin/env python3
"""
gen_secrets.py -- fake leaked credentials and secrets. These are randomly
generated and FAKE (they authenticate to nothing) but match the FORMATS that
GCP Sensitive Data Protection detects: GCP API keys, GCP service-account JSON
keys, AWS access keys, JSON Web Tokens, private keys, passwords, and DB
connection strings. This is the classic "secrets accidentally committed to a
bucket" finding.

Outputs a few realistic-looking files repeated until the size target is hit:
  credentials/app_config.env
  credentials/service-account-key.json
  credentials/secrets_dump.txt

Usage: python3 gen_secrets.py <out_dir> <size e.g. 10KB>
"""

import base64
import json
import os
import sys

from faker import Faker
from common import parse_size

fake = Faker()


def b64(n):
    """n random bytes, base64url, no padding -- looks like a real token."""
    return base64.urlsafe_b64encode(os.urandom(n)).decode().rstrip("=")


def gcp_api_key():
    # GCP API keys start with "AIza" + 35 url-safe chars.
    return "AIza" + b64(27)[:35]


def aws_key():
    return "AKIA" + fake.lexify("?" * 16).upper()


def jwt():
    # header.payload.signature -- three base64url segments.
    return "%s.%s.%s" % (b64(20), b64(60), b64(32))


def fake_private_key():
    body = "\n".join(b64(48) for _ in range(12))
    return "-----BEGIN RSA PRIVATE KEY-----\n%s\n-----END RSA PRIVATE KEY-----" % body


def service_account_json():
    proj = fake.slug()
    sa = "demo-sa@%s.iam.gserviceaccount.com" % proj
    return json.dumps({
        "type": "service_account",
        "project_id": proj,
        "private_key_id": b64(20),
        "private_key": fake_private_key() + "\n",
        "client_email": sa,
        "client_id": fake.numerify("#" * 21),
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
    }, indent=2)


def env_block():
    return (
        "# leaked application config -- DO NOT COMMIT (but here it is)\n"
        "DB_HOST=%s\n"
        "DB_USER=%s\n"
        "DB_PASSWORD=%s\n"
        "DATABASE_URL=postgres://%s:%s@%s:5432/app\n"
        "GCP_API_KEY=%s\n"
        "AWS_ACCESS_KEY_ID=%s\n"
        "AWS_SECRET_ACCESS_KEY=%s\n"
        "JWT=%s\n"
        "STRIPE_SECRET_KEY=sk_live_%s\n\n"
        % (fake.domain_name(), fake.user_name(), fake.password(length=20),
           fake.user_name(), fake.password(length=16), fake.domain_name(),
           gcp_api_key(), aws_key(), b64(30), jwt(), fake.lexify("?" * 24))
    )


def main(out_dir, size):
    target = parse_size(size)
    cred_dir = os.path.join(out_dir, "credentials")
    os.makedirs(cred_dir, exist_ok=True)

    # The .env file is what we size against; the other two are one-shot samples.
    with open(os.path.join(cred_dir, "service-account-key.json"), "w") as f:
        f.write(service_account_json())
    with open(os.path.join(cred_dir, "secrets_dump.txt"), "w") as f:
        f.write("PRIVATE KEY:\n%s\n\nGCP_API_KEY=%s\nJWT=%s\n"
                % (fake_private_key(), gcp_api_key(), jwt()))

    env_path = os.path.join(cred_dir, "app_config.env")
    n = 0
    with open(env_path, "w") as f:
        while True:
            f.write(env_block())
            n += 1
            if n % 10 == 0:
                f.flush()
                if os.path.getsize(env_path) >= target:
                    break
    print("secrets: wrote credential files (%d config blocks) to %s"
          % (n, cred_dir))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
