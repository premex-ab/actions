#!/usr/bin/env bash
# Shared by s3-upload-artifact and s3-download-artifact. Talks to any S3-compatible store with
# curl's built-in SigV4 signing, so it runs unchanged on Linux and macOS runners (including
# Apple's bash 3.2) and needs neither the AWS CLI nor Docker. Path-style URLs:
# <endpoint>/<bucket>/<key>.
set -euo pipefail

s3_fail() { echo "::error::$*" >&2; exit 1; }

s3_trim() { # value -> value without leading/trailing whitespace
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  printf '%s' "${value%"${value##*[![:space:]]}"}"
}

s3_require_curl() {
  local version major minor
  version="$(curl --version | head -n 1 | cut -d' ' -f2)"
  major="${version%%.*}"; minor="${version#*.}"; minor="${minor%%.*}"
  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || s3_fail "Could not read the curl version ('$version')"
  if (( major < 7 || (major == 7 && minor < 76) )); then
    s3_fail "curl $version is too old: --aws-sigv4 and --fail-with-body need curl 7.76 or later (tested with curl 8)"
  fi
}

s3_init() {
  s3_require_curl
  S3_ENDPOINT="$(s3_trim "${S3_ENDPOINT:-}")"
  S3_ENDPOINT="${S3_ENDPOINT%/}"
  S3_BUCKET="$(s3_trim "${S3_BUCKET:-}")"
  S3_REGION="$(s3_trim "${S3_REGION:-us-east-1}")"
  S3_ACCESS_KEY_ID="$(s3_trim "${S3_ACCESS_KEY_ID:-}")"
  S3_SECRET_ACCESS_KEY="$(s3_trim "${S3_SECRET_ACCESS_KEY:-}")"
  [[ -n "$S3_ACCESS_KEY_ID" && -n "$S3_SECRET_ACCESS_KEY" ]] || s3_fail "access-key-id and secret-access-key are required"
  [[ "$S3_ENDPOINT" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?$ ]] \
    || s3_fail "endpoint must be scheme://host[:port], got '$S3_ENDPOINT'"
  [[ "$S3_BUCKET" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || s3_fail "'$S3_BUCKET' is not a valid bucket name"
  [[ "$S3_REGION" =~ ^[A-Za-z0-9-]+$ ]] || s3_fail "'$S3_REGION' is not a valid region"
  # A control character (a pasted newline) could otherwise add lines to curl's config.
  [[ "$S3_ACCESS_KEY_ID$S3_SECRET_ACCESS_KEY" != *[[:cntrl:]]* ]] \
    || s3_fail "access-key-id or secret-access-key contains a control character"
  if [[ "$S3_ENDPOINT" == http://* ]]; then
    echo "::warning::$S3_ENDPOINT is plain http: request bodies are not covered by the signature, so anyone on the network path can read or replace artifacts. Use https." >&2
  fi

  S3_WORK="$(mktemp -d "${RUNNER_TEMP:-/tmp}/s3-artifact.XXXXXX")"
  trap 'rm -rf "$S3_WORK"' EXIT
  # Abort a transfer that stalls below 1 KiB/s for a minute instead of hanging the job.
  S3_CURL_ARGS=(--silent --show-error --fail-with-body --retry 3 --connect-timeout 20 --speed-limit 1024 --speed-time 60)
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

s3_check_name() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ && "$1" != "." && "$1" != ".." ]] \
    || s3_fail "name '$1' may contain only letters, digits, '.', '_' and '-'"
}

# Object keys are built from validated parts only, so they never need URL encoding.
s3_check_prefix() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ && "/$1/" != *"/../"* && "/$1/" != *"/./"* ]] \
    || s3_fail "prefix '$1' may contain only letters, digits, '.', '_', '-' and '/'-separated segments"
}

# Prints the <Code> and <Message> of an S3 error response. They never contain the secret.
s3_explain() { # response-file what
  local code message
  code="$(sed -n 's:.*<Code>\(.*\)</Code>.*:\1:p' "$1" 2> /dev/null | head -n 1)"
  message="$(sed -n 's:.*<Message>\(.*\)</Message>.*:\1:p' "$1" 2> /dev/null | head -n 1)"
  echo "::error::$2 failed${code:+: $code}${message:+: $message}" >&2
}

s3_curl() { # method key [curl args...]
  local method="$1" key="$2"; shift 2
  printf '%s\n' "$S3_CURL_CONFIG" | curl "${S3_CURL_ARGS[@]}" -K - \
    --aws-sigv4 "aws:amz:$S3_REGION:s3" -H 'x-amz-content-sha256: UNSIGNED-PAYLOAD' \
    -X "$method" "$@" "$S3_ENDPOINT/$S3_BUCKET/$key"
}

s3_put() { # file key [curl args...]
  local file="$1" key="$2"; shift 2
  s3_curl PUT "$key" --upload-file "$file" --output "$S3_WORK/response" "$@" \
    || { s3_explain "$S3_WORK/response" "Uploading s3://$S3_BUCKET/$key"; return 1; }
}

s3_get() { # key file
  s3_curl GET "$1" --output "$2" \
    || { s3_explain "$2" "Downloading s3://$S3_BUCKET/$1"; rm -f "$2"; return 1; }
}

s3_sha256() {
  if command -v sha256sum > /dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

s3_is_bsdtar() { tar --version 2> /dev/null | grep -q bsdtar; }
