#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../s3-artifact-lib/s3.sh
source "$(dirname "$0")/../s3-artifact-lib/s3.sh"

s3_init
s3_check_key_part "$S3_NAME"
s3_check_key_part "$S3_PREFIX"
case "$S3_IF_NO_FILES_FOUND" in warn|error|ignore) ;; *) s3_fail "if-no-files-found must be warn, error or ignore";; esac

cd "${S3_WORKING_DIRECTORY:-.}"
# ** needs bash 4 (macOS ships 3.2 as /bin/bash); without it ** matches like *.
shopt -s nullglob dotglob
shopt -s globstar 2> /dev/null || true
list="$S3_WORK/files"
: > "$list"
while IFS= read -r pattern || [[ -n "$pattern" ]]; do
  pattern="${pattern#"${pattern%%[![:space:]]*}"}"; pattern="${pattern%"${pattern##*[![:space:]]}"}"
  [[ -z "$pattern" ]] && continue
  [[ "$pattern" == /* || "/$pattern/" == *"/../"* ]] && s3_fail "'$pattern' must be relative to the working directory, without '..'"
  # Split only on newlines so a path with spaces stays one pattern; still glob it.
  IFS=$'\n'
  # shellcheck disable=SC2206 # the pattern is meant to glob
  matches=($pattern)
  IFS=$' \t\n'
  for match in ${matches[@]+"${matches[@]}"}; do [[ -e "$match" ]] && printf '%s\n' "${match%/}" >> "$list"; done
done <<< "$S3_PATH"
sort -u -o "$list" "$list"

if [[ ! -s "$list" ]]; then
  message="No files were found for '$S3_NAME' with the provided path."
  case "$S3_IF_NO_FILES_FOUND" in
    error) s3_fail "$message" ;;
    warn) echo "::warning::$message No artifact will be uploaded." ;;
  esac
  exit 0
fi

archive="$S3_WORK/$S3_NAME.tar.gz"
tar -czf "$archive" -T "$list"
digest="$(s3_sha256 "$archive")"
printf '%s\n' "$digest" > "$archive.sha256"
size="$(wc -c < "$archive" | tr -d ' ')"
key="$S3_PREFIX/$S3_NAME.tar.gz"

s3_put "$archive" "$key" || s3_fail "Could not upload s3://$S3_BUCKET/$key"
s3_put "$archive.sha256" "$key.sha256" || s3_fail "Could not upload s3://$S3_BUCKET/$key.sha256"

echo "Uploaded $size bytes to s3://$S3_BUCKET/$key (sha256 $digest)"
{
  echo "key=$key"
  echo "sha256=$digest"
  echo "size=$size"
} >> "${GITHUB_OUTPUT:-/dev/null}"
