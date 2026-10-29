#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/set-testflight-secrets.sh \
    --issuer-id <app_store_connect_issuer_id> \
    --key-id <app_store_connect_key_id> \
    --api-key-path </path/to/AuthKey_XXXX.p8> \
    --certificate-path </path/to/distribution-certificate.p12> \
    --certificate-password <p12_password> \
    [--repo <owner/name>]

This sets the GitHub repository secrets required by .github/workflows/testflight.yml:
  - APPSTORE_API_ISSUER_ID
  - APPSTORE_API_KEY_ID
  - APPSTORE_API_PRIVATE_KEY
  - DISTRIBUTION_CERTIFICATE_BASE64
  - DISTRIBUTION_CERTIFICATE_PASSWORD
EOF
}

repo_from_origin() {
  local origin_url
  origin_url="$(git remote get-url origin)"

  case "$origin_url" in
    git@github.com:*)
      origin_url="${origin_url#git@github.com:}"
      origin_url="${origin_url%.git}"
      printf '%s\n' "$origin_url"
      ;;
    https://github.com/*)
      origin_url="${origin_url#https://github.com/}"
      origin_url="${origin_url%.git}"
      printf '%s\n' "$origin_url"
      ;;
    *)
      echo "Unsupported origin URL: $origin_url" >&2
      exit 1
      ;;
  esac
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Missing file: $path" >&2
    exit 1
  fi
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

issuer_id=""
key_id=""
api_key_path=""
certificate_path=""
certificate_password=""
repo=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issuer-id)
      issuer_id="${2:-}"
      shift 2
      ;;
    --key-id)
      key_id="${2:-}"
      shift 2
      ;;
    --api-key-path)
      api_key_path="${2:-}"
      shift 2
      ;;
    --certificate-path)
      certificate_path="${2:-}"
      shift 2
      ;;
    --certificate-password)
      certificate_password="${2:-}"
      shift 2
      ;;
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$issuer_id" || -z "$key_id" || -z "$api_key_path" || -z "$certificate_path" || -z "$certificate_password" ]]; then
  usage >&2
  exit 1
fi

require_command gh
require_command git
require_command base64
require_file "$api_key_path"
require_file "$certificate_path"

if [[ -z "$repo" ]]; then
  repo="$(repo_from_origin)"
fi

certificate_base64="$(base64 < "$certificate_path" | tr -d '\r\n')"

echo "Setting TestFlight secrets for $repo"

gh secret set APPSTORE_API_ISSUER_ID --repo "$repo" --body "$issuer_id"
gh secret set APPSTORE_API_KEY_ID --repo "$repo" --body "$key_id"
gh secret set APPSTORE_API_PRIVATE_KEY --repo "$repo" < "$api_key_path"
gh secret set DISTRIBUTION_CERTIFICATE_BASE64 --repo "$repo" --body "$certificate_base64"
gh secret set DISTRIBUTION_CERTIFICATE_PASSWORD --repo "$repo" --body "$certificate_password"

echo "Done. Repository secrets updated for $repo."
