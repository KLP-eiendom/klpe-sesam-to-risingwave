#!/usr/bin/env python3
"""fetch_vault_secrets.py — Fetch secrets from HashiCorp Vault KV v1.

Usage:
    python fetch_vault_secrets.py <env_file> [localdev_file]

Reads VaultOptions__ variables from <env_file>, authenticates to Vault,
fetches secrets from kv/Risingwave/{env}, then prints resolved KEY=VALUE
pairs to stdout. Non-VaultOptions lines in <env_file> (e.g. *_SINK_MODE)
are passed through. [localdev_file] overrides are applied last.

Auth priority: VaultOptions__TokenId → VaultOptions__K8TokenId (K8s SA)
"""

import json
import os
import ssl
import sys
import urllib.request


def load_env_file(path):
    """Parse key=value file, return dict. Skips blank lines and comments."""
    env = {}
    if not path or not os.path.exists(path):
        return env
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            env[key.strip()] = value.strip()
    return env


def _make_ssl_ctx():
    # Vault server uses a self-signed certificate — verification intentionally disabled
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def vault_k8s_login(server, k8_token, role_name, mountpoint):
    """Authenticate via Kubernetes SA token, return Vault client token."""
    url = f"{server}/v1/auth/{mountpoint}/login"
    payload = json.dumps({"jwt": k8_token, "role": role_name}).encode()
    req = urllib.request.Request(
        url, data=payload, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, context=_make_ssl_ctx()) as resp:
            data = json.loads(resp.read())
        return data["auth"]["client_token"]
    except urllib.error.HTTPError as exc:
        print(f"ERROR: Vault K8s login failed ({exc.code}) at '{url}'", file=sys.stderr)
        print(exc.read().decode(), file=sys.stderr)
        sys.exit(1)


def vault_read_kv1(server, token, path):
    """Read a KV v1 secret at `path` (e.g. 'Risingwave/dev'), return dict."""
    url = f"{server}/v1/kv/{path}"
    req = urllib.request.Request(url, headers={"X-Vault-Token": token})
    try:
        with urllib.request.urlopen(req, context=_make_ssl_ctx()) as resp:
            data = json.loads(resp.read())
        return data.get("data", {})
    except urllib.error.HTTPError as exc:
        print(f"ERROR: Vault returned {exc.code} for path '{path}'", file=sys.stderr)
        print(exc.read().decode(), file=sys.stderr)
        sys.exit(1)


def fetch_secrets(server, token, prefix, secrets_raw):
    """Fetch all secrets for the given secret names, return merged dict."""
    secrets = [s.strip() for s in secrets_raw.replace(",", " ").split() if s.strip()]
    if not prefix.endswith("/"):
        prefix += "/"
    result = {}
    for secret in secrets:
        path = f"{prefix}{secret}"
        kv = vault_read_kv1(server, token, path)
        result.update(kv)
    return result


def main():
    env_file = sys.argv[1] if len(sys.argv) > 1 else None
    localdev_file = sys.argv[2] if len(sys.argv) > 2 else None

    file_env = load_env_file(env_file)

    # VaultOptions: env file first, fall back to os.environ (CI sets these via variable group)
    def _vopt(key, default=""):
        return file_env.get(key) or os.environ.get(key, default)

    server = _vopt("VaultOptions__Server").rstrip("/")
    prefix = _vopt("VaultOptions__Prefix", "Risingwave/")
    secrets_raw = _vopt("VaultOptions__Secrets")
    token_id = _vopt("VaultOptions__TokenId")
    k8_token_id = _vopt("VaultOptions__K8TokenId")
    vault_role = _vopt("VaultOptions__VaultRoleName")
    mountpoint = _vopt("VaultOptions__K8Mountpoint", "kubernetes")

    # Non-VaultOptions vars from the env file (sink modes, operational flags)
    passthrough = {k: v for k, v in file_env.items() if not k.startswith("VaultOptions__")}

    if not server:
        print("ERROR: VaultOptions__Server not set in env file", file=sys.stderr)
        sys.exit(1)

    if not secrets_raw:
        print("ERROR: VaultOptions__Secrets not set in env file", file=sys.stderr)
        sys.exit(1)

    # Resolve auth token
    if token_id:
        vault_token = token_id
    elif k8_token_id:
        if not vault_role:
            print(
                "ERROR: VaultOptions__VaultRoleName required when using K8TokenId",
                file=sys.stderr,
            )
            sys.exit(1)
        vault_token = vault_k8s_login(server, k8_token_id, vault_role, mountpoint)
    else:
        print(
            "ERROR: Neither VaultOptions__TokenId nor VaultOptions__K8TokenId set",
            file=sys.stderr,
        )
        sys.exit(1)

    vault_secrets = fetch_secrets(server, vault_token, prefix, secrets_raw)

    # Merge: vault base → env file passthrough overrides → localdev overrides
    result = {}
    result.update(vault_secrets)
    result.update(passthrough)
    result.update(load_env_file(localdev_file))

    for key, value in result.items():
        sys.stdout.write(f"{key}={value}\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
