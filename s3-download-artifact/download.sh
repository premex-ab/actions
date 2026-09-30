#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../s3-artifact-lib/s3.sh
source "$(dirname "$0")/../s3-artifact-lib/s3.sh"

s3_init
s3_check_name "$S3_NAME"
s3_check_prefix "$S3_PREFIX"
expected="$(s3_trim "${S3_EXPECTED_SHA256:-}" | tr '[:upper:]' '[:lower:]')"
[[ -z "$expected" || "$expected" =~ ^[0-9a-f]{64}$ ]] || s3_fail "sha256 must be 64 hexadecimal characters"

key="$S3_PREFIX/$S3_NAME.tar.gz"
archive="$S3_WORK/$S3_NAME.tar.gz"
s3_get "$key" "$archive" || exit 1
actual="$(s3_sha256 "$archive")"

if [[ -n "$expected" ]]; then
  # Pinned by the uploading job (for example through job outputs): the bucket cannot vouch for itself.
  [[ "$expected" == "$actual" ]] || s3_fail "Checksum mismatch for $key: the uploading job reported $expected, the bucket holds $actual"
else
  s3_get "$key.sha256" "$archive.sha256" || exit 1
  stored="$(tr -d '[:space:]' < "$archive.sha256")"
  [[ "$stored" == "$actual" ]] || s3_fail "Checksum mismatch for $key: its .sha256 says $stored, the archive is $actual. An upload may have failed halfway or two jobs may share this name."
fi

# Uploads contain only regular files. Refuse anything else before unpacking a single byte.
listing="$(tar -tvzf "$archive")"
names="$(tar -tzf "$archive")"
if grep -qE '^[lhbcp]' <<< "$listing" || grep -q ' link to ' <<< "$listing"; then
  s3_fail "$key contains links or special files; s3-upload-artifact never creates those"
fi
if grep -qE '(^/|(^|/)\.\.(/|$))' <<< "$names"; then
  s3_fail "$key contains absolute or '..' paths"
fi

destination="${S3_DESTINATION:-.}"
[[ "$destination" == -* ]] && destination="./$destination"
mkdir -p "$destination"
tar -xzf "$archive" -C "$destination"

echo "Downloaded s3://$S3_BUCKET/$key into $destination (sha256 $actual)"
{
  echo "key=$key"
  echo "sha256=$actual"
  echo "download-path=$(cd "$destination" && pwd)"
} >> "${GITHUB_OUTPUT:-/dev/null}"
