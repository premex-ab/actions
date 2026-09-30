#!/usr/bin/env bash
# Shared by s3-upload-artifact and s3-download-artifact. Talks to any S3-compatible store with
# curl's built-in SigV4 signing (curl 7.75+), so it runs unchanged on Linux and macOS runners and
# needs neither the AWS CLI nor Docker. Path-style URLs: <endpoint>/<bucket>/<key>.
set -euo pipefail

s3_fail() { echo "::error::$*" >&2; exit 1; }

s3_init() {
  : "${S3_ENDPOINT:?}" "${S3_BUCKET:?}" "${S3_ACCESS_KEY_ID:?}" "${S3_SECRET_ACCESS_KEY:?}"
  S3_REGION="${S3_REGION:-us-east-1}"
  S3_ENDPOINT="${S3_ENDPOINT%/}"
  [[ "$S3_ENDPOINT" =~ ^https?://[^/]+$ ]] || s3_fail "endpoint must be scheme://host[:port], got '$S3_ENDPOINT'"
  [[ "$S3_BUCKET" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || s3_fail "'$S3_BUCKET' is not a valid bucket name"
  [[ "$S3_REGION" =~ ^[A-Za-z0-9-]+$ ]] || s3_fail "'$S3_REGION' is not a valid region"
  S3_WORK="$(mktemp -d "${RUNNER_TEMP:-/tmp}/s3-artifact.XXXXXX")"
  trap 'rm -rf "$S3_WORK"' EXIT
  S3_CURL_ARGS=(--silent --show-error --fail-with-body --retry 3 --connect-timeout 20)
  if [[ -n "${S3_CA_CERTIFICATE:-}" ]]; then
    printf '%s\n' "$S3_CA_CERTIFICATE" > "$S3_WORK/ca.pem"
    S3_CURL_ARGS+=(--cacert "$S3_WORK/ca.pem")
  fi
  # Credentials go to curl through a config file on stdin, never on its command line.
  local id secret
  id="${S3_ACCESS_KEY_ID//\\/\\\\}"; id="${id//\"/\\\"}"
  secret="${S3_SECRET_ACCESS_KEY//\\/\\\\}"; secret="${secret//\"/\\\"}"
  S3_CURL_CONFIG="user = \"$id:$secret\""
}

# Object keys are built from validated parts only, so they never need URL encoding.
s3_check_key_part() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ && "/$1/" != *"/../"* && "/$1/" != *"/./"* ]] \
    || s3_fail "'$1' may contain only letters, digits, '.', '_', '-' and '/'-separated segments"
}

s3_curl() { # method key [curl args...]
  local method="$1" key="$2"; shift 2
  printf '%s\n' "$S3_CURL_CONFIG" | curl "${S3_CURL_ARGS[@]}" -K - \
    --aws-sigv4 "aws:amz:$S3_REGION:s3" -H 'x-amz-content-sha256: UNSIGNED-PAYLOAD' \
    -X "$method" "$@" "$S3_ENDPOINT/$S3_BUCKET/$key"
}

s3_put() { s3_curl PUT "$2" --upload-file "$1" --output /dev/null; }  # file key
s3_get() { s3_curl GET "$1" --output "$2"; }                          # key file

s3_sha256() {
  if command -v sha256sum > /dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
