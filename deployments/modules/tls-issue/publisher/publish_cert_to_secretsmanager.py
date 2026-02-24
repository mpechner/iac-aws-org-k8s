#!/usr/bin/env python3
"""
Publish TLS cert from Kubernetes Secret (mounted at /etc/tls) to AWS Secrets Manager.
Idempotent: updates only when the certificate fingerprint changes.
JSON payload: fqdn, fingerprint_sha256, fullchain_pem, privkey_pem, chain_pem.
"""

import os
import sys
import json
import logging
from pathlib import Path

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
from cryptography import x509
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes, serialization

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
logger = logging.getLogger(__name__)

TLS_DIR = Path(os.environ.get("TLS_DIR", "/etc/tls"))
CERT_FILE = TLS_DIR / "tls.crt"
KEY_FILE = TLS_DIR / "tls.key"
REQUEST_TIMEOUT = 30
MAX_RETRIES = 3


def load_pem(path: Path) -> bytes:
    with open(path, "rb") as f:
        return f.read()


def fingerprint_sha256(cert_der: bytes) -> str:
    cert = x509.load_der_x509_certificate(cert_der, default_backend())
    return cert.fingerprint(hashes.SHA256()).hex()


def split_fullchain(fullchain_pem: bytes) -> tuple[bytes, bytes]:
    """Return (leaf_pem, chain_pem). Chain is everything after the first certificate."""
    parts = fullchain_pem.strip().split(b"\n\n-----BEGIN CERTIFICATE-----")
    if not parts:
        raise ValueError("No certificate found in fullchain")
    leaf = parts[0].strip()
    if not leaf.startswith(b"-----BEGIN CERTIFICATE-----"):
        leaf = b"-----BEGIN CERTIFICATE-----\n" + leaf
    chain_pem = b""
    if len(parts) > 1:
        chain_parts = [b"-----BEGIN CERTIFICATE-----" + p.strip() for p in parts[1:]]
        chain_pem = b"\n".join(chain_parts)
    return leaf, chain_pem


def get_leaf_der(fullchain_pem: bytes) -> bytes:
    leaf_pem, _ = split_fullchain(fullchain_pem)
    cert = x509.load_pem_x509_certificate(leaf_pem, default_backend())
    return cert.public_bytes(serialization.Encoding.DER)


def main() -> int:
    # ── Step 1: read and validate environment ────────────────────────────────
    logger.info("=== Step 1: environment ===")
    region      = os.environ.get("AWS_REGION")
    secret_name = os.environ.get("AWS_SECRET_NAME")
    kms_key_id  = os.environ.get("KMS_KEY_ID", "")
    vpn_fqdn    = os.environ.get("VPN_FQDN")
    tls_secret  = os.environ.get("TLS_SECRET_NAME", "(not set)")
    tls_ns      = os.environ.get("TLS_SECRET_NAMESPACE", "(not set)")

    logger.info("  AWS_REGION           = %s", region or "(not set)")
    logger.info("  AWS_SECRET_NAME      = %s", secret_name or "(not set)")
    logger.info("  VPN_FQDN             = %s", vpn_fqdn or "(not set)")
    logger.info("  KMS_KEY_ID           = %s", kms_key_id or "(empty — using aws/secretsmanager)")
    logger.info("  TLS_SECRET_NAME      = %s", tls_secret)
    logger.info("  TLS_SECRET_NAMESPACE = %s", tls_ns)
    logger.info("  TLS_DIR              = %s", TLS_DIR)

    for val, name in [
        (region, "AWS_REGION"),
        (secret_name, "AWS_SECRET_NAME"),
        (vpn_fqdn, "VPN_FQDN"),
    ]:
        if not val:
            logger.error("Missing required env: %s", name)
            return 1

    # ── Step 2: read TLS files ───────────────────────────────────────────────
    logger.info("=== Step 2: reading TLS files from %s ===", TLS_DIR)
    if not CERT_FILE.exists():
        logger.error("tls.crt not found at %s", CERT_FILE)
        return 1
    if not KEY_FILE.exists():
        logger.error("tls.key not found at %s", KEY_FILE)
        return 1

    try:
        fullchain_pem = load_pem(CERT_FILE)
        privkey_pem   = load_pem(KEY_FILE)
    except OSError as e:
        logger.error("Failed to read TLS files: %s", e)
        return 1

    logger.info("  tls.crt size = %d bytes", len(fullchain_pem))
    logger.info("  tls.key size = %d bytes", len(privkey_pem))

    # ── Step 3: compute fingerprint ──────────────────────────────────────────
    logger.info("=== Step 3: computing certificate fingerprint ===")
    leaf_der    = get_leaf_der(fullchain_pem)
    fingerprint = fingerprint_sha256(leaf_der)
    _, chain_pem = split_fullchain(fullchain_pem)
    logger.info("  fingerprint (sha256) = %s", fingerprint)

    payload = {
        "fqdn":              vpn_fqdn,
        "fingerprint_sha256": fingerprint,
        "fullchain_pem":     fullchain_pem.decode("utf-8"),
        "privkey_pem":       privkey_pem.decode("utf-8"),
        "chain_pem":         chain_pem.decode("utf-8") if chain_pem else "",
    }

    # ── Step 4: create boto3 client ──────────────────────────────────────────
    logger.info("=== Step 4: creating Secrets Manager client (region=%s) ===", region)
    config = Config(
        connect_timeout=REQUEST_TIMEOUT,
        read_timeout=REQUEST_TIMEOUT,
        retries={"max_attempts": MAX_RETRIES, "mode": "standard"},
    )
    client = boto3.client("secretsmanager", region_name=region, config=config)

    # ── Step 5: check if secret exists ──────────────────────────────────────
    logger.info("=== Step 5: checking existing secret '%s' ===", secret_name)
    try:
        current = client.get_secret_value(SecretId=secret_name)
        logger.info("  Secret exists.")
    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code == "ResourceNotFoundException":
            logger.info("  Secret does not exist — will create.")
            current = None
        else:
            logger.error("  GetSecretValue failed: %s", code)
            return 1
    except Exception as e:
        logger.error("  GetSecretValue error: %s", e)
        return 1

    # ── Step 6: update or create ─────────────────────────────────────────────
    if current:
        logger.info("=== Step 6: comparing fingerprints ===")
        try:
            existing_fp = json.loads(current["SecretString"]).get("fingerprint_sha256", "")
            logger.info("  existing  = %s", existing_fp)
            logger.info("  current   = %s", fingerprint)
            if existing_fp == fingerprint:
                logger.info("  Fingerprint unchanged — skipping update.")
                return 0
        except (KeyError, json.JSONDecodeError):
            logger.info("  Could not parse existing secret — forcing update.")

        logger.info("=== Step 6: updating secret (PutSecretValue) ===")
        try:
            client.put_secret_value(
                SecretId=secret_name,
                SecretString=json.dumps(payload),
            )
            logger.info("  Updated secret %s (fingerprint %s...).", secret_name, fingerprint[:16])
        except ClientError as e:
            logger.error("  PutSecretValue failed: %s", e.response["Error"]["Code"])
            return 1
        except Exception as e:
            logger.error("  PutSecretValue error: %s", e)
            return 1
        return 0

    logger.info("=== Step 6: creating secret (CreateSecret) ===")
    try:
        create_kwargs = {"Name": secret_name, "SecretString": json.dumps(payload)}
        if kms_key_id:
            create_kwargs["KmsKeyId"] = kms_key_id
        client.create_secret(**create_kwargs)
        logger.info("  Created secret %s (fingerprint %s...).", secret_name, fingerprint[:16])
    except ClientError as e:
        logger.error("  CreateSecret failed: %s", e.response["Error"]["Code"])
        return 1
    except Exception as e:
        logger.error("  CreateSecret error: %s", e)
        return 1

    logger.info("=== Done ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
