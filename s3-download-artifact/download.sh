#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../s3-artifact-lib/s3.sh
source "$(dirname "$0")/../s3-artifact-lib/s3.sh"

s3_init
s3_check_key_part "$S3_NAME"
s3_check_key_part "$S3_PREFIX"

key="$S3_PREFIX/$S3_NAME.tar.gz"
archive="$S3_WORK/$S3_NAME.tar.gz"
s3_get "$key" "$archive" || s3_fail "Could not download s3://$S3_BUCKET/$key"
s3_get "$key.sha256" "$archive.sha256" || s3_fail "Could not download s3://$S3_BUCKET/$key.sha256"

expected="$(tr -d '[:space:]' < "$archive.sha256")"
actual="$(s3_sha256 "$archive")"
[[ "$expected" == "$actual" ]] || s3_fail "Checksum mismatch for $key: expected $expected, got $actual"

destination="${S3_DESTINATION:-.}"
mkdir -p "$destination"
tar -xzf "$archive" -C "$destination"

echo "Downloaded s3://$S3_BUCKET/$key into $destination (sha256 $actual)"
{
  echo "key=$key"
  echo "sha256=$actual"
  echo "download-path=$(cd "$destination" && pwd)"
} >> "${GITHUB_OUTPUT:-/dev/null}"
