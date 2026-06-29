#!/usr/bin/env python3
"""
Welcome to gen_secrets.py!
This script creates fake "secrets".
Secrets are things like passwords, API keys, and database connection strings.
If a hacker finds these, they can control your systems.

We generate fake secrets that look 100% real (they have the right length,
characters, and prefixes), but they don't actually work.

We generate:
1. Google Cloud (GCP) API keys (they always start with "AIza").
2. Google Cloud Service Account Keys (JSON files).
3. Amazon Web Services (AWS) Keys (start with "AKIA").
4. JSON Web Tokens (JWT) (used for logins).
5. Database connection strings (contains username/password).
6. Private encryption keys (RSA).

We save these in files like `app_config.env` and `service-account-key.json`.
In real life, programmers sometimes accidentally upload these files to public
places (like GitHub). We put them here to make sure our security scanner
can find them!
"""

import base64
import json
import os
import sys

from faker import Faker
from common import parse_size

fake = Faker()


def b64(n):
    """
    Generates 'n' random bytes and converts them to a Base64 text string.
    This is how many computer keys and tokens are formatted.
    """
    return base64.urlsafe_b64encode(os.urandom(n)).decode().rstrip("=")


def gcp_api_key():
    # Real GCP API keys always start with "AIza" followed by 35 characters.
    return "AIza" + b64(27)[:35]


def aws_key():
    # Real AWS keys start with "AKIA" followed by 16 uppercase letters/numbers.
    return "AKIA" + fake.lexify("?" * 16).upper()


def jwt():
    # A JSON Web Token looks like three random blocks of text separated by dots.
    # header.payload.signature
    return "%s.%s.%s" % (b64(20), b64(60), b64(32))


def fake_private_key():
    # A private key is used for encryption. It has a specific header and footer
    # and a block of base64 text in the middle.
    body = "\n".join(b64(48) for _ in range(12))
    return "-----BEGIN RSA PRIVATE KEY-----\n%s\n-----END RSA PRIVATE KEY-----" % body


def service_account_json():
    # This is a fake Google Cloud Service Account key file.
    # It is a JSON file that contains a private key and email.
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
    # This creates a block of text that looks like a configuration file (.env)
    # where a programmer might have written down all their passwords.
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

    # 1. Write the fake service account JSON key.
    with open(os.path.join(cred_dir, "service-account-key.json"), "w") as f:
        f.write(service_account_json())
        
    # 2. Write a file that looks like a dump of various keys.
    with open(os.path.join(cred_dir, "secrets_dump.txt"), "w") as f:
        f.write("PRIVATE KEY:\n%s\n\nGCP_API_KEY=%s\nJWT=%s\n"
                % (fake_private_key(), gcp_api_key(), jwt()))

    # 3. Keep writing the .env file until it reaches the target size.
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
