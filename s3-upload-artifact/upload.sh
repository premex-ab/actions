#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../s3-artifact-lib/s3.sh
source "$(dirname "$0")/../s3-artifact-lib/s3.sh"

s3_init
s3_check_name "$S3_NAME"
s3_check_prefix "$S3_PREFIX"
case "$S3_IF_NO_FILES_FOUND" in warn|error|ignore) ;; *) s3_fail "if-no-files-found must be warn, error or ignore";; esac
case "${S3_INCLUDE_HIDDEN_FILES:-false}" in true|false) ;; *) s3_fail "include-hidden-files must be true or false";; esac
case "${S3_IMMUTABLE:-false}" in true|false) ;; *) s3_fail "immutable must be true or false";; esac

directory="${S3_WORKING_DIRECTORY:-.}"
[[ -d "$directory" ]] || s3_fail "working-directory '$directory' does not exist"
cd "$directory"

shopt -s nullglob
[[ "${S3_INCLUDE_HIDDEN_FILES:-false}" == true ]] && shopt -s dotglob
# ** needs bash 4 (macOS ships 3.2 as /bin/bash).
globstar=false
shopt -s globstar 2> /dev/null && globstar=true

# Every file to archive, NUL-separated. Directories are expanded here, following symlinks, so the
# archive holds only regular files: no links to recreate (or abuse) on the other side.
list="$S3_WORK/files"
: > "$list"
while IFS= read -r pattern || [[ -n "$pattern" ]]; do
  pattern="$(s3_trim "$pattern")"
  [[ -z "$pattern" ]] && continue
  [[ "$pattern" == /* || "/$pattern/" == *"/../"* ]] \
    && s3_fail "'$pattern' must be relative to the working directory, without '..'"
  [[ "$pattern" == *"**"* && "$globstar" == false ]] \
    && s3_fail "'$pattern' uses **, which needs bash 4 or later; this runner has bash $BASH_VERSION"
  # Split only on newlines so a path with spaces stays one pattern; still glob it.
  IFS=$'\n'
  # shellcheck disable=SC2206 # the pattern is meant to glob
  matches=($pattern)
  IFS=$' \t\n'
  for match in ${matches[@]+"${matches[@]}"}; do
    match="${match%/}"
    # Older bash globs '.*' to '.' and '..' as well: never let a glob climb out or take everything.
    case "$match" in ..|*/..|*/.) continue ;; .) [[ "$pattern" == "." ]] || continue ;; esac
    [[ -e "$match" ]] || continue
    start="./$match"
    [[ "$match" == "." ]] && start="."
    if [[ "${S3_INCLUDE_HIDDEN_FILES:-false}" == true ]]; then
      find -L "$start" -type f -print0 >> "$list"
    else
      find -L "$start" -path '*/.*' -prune -o -type f -print0 >> "$list"
    fi
  done
done <<< "$S3_PATH"

if [[ ! -s "$list" ]]; then
  message="No files were found for '$S3_NAME' with the provided path."
  case "$S3_IF_NO_FILES_FOUND" in
    error) s3_fail "$message" ;;
    warn) echo "::warning::$message No artifact will be uploaded." ;;
  esac
  exit 0
fi
sort -z -u -o "$list" "$list"

archive="$S3_WORK/$S3_NAME.tar.gz"
tar_flags=()
if s3_is_bsdtar; then
  # Store what symlinks point to, not the links. Without the other two, macOS tar adds
  # AppleDouble ._* entries and extended attributes.
  export COPYFILE_DISABLE=1
  tar_flags=(-L --no-mac-metadata --no-xattrs)
else
  # Two paths to one file (through a symlink) become two copies, not a hard link entry.
  tar_flags=(--dereference --hard-dereference)
fi
tar -c -z ${tar_flags[@]+"${tar_flags[@]}"} --null -T "$list" -f "$archive"
digest="$(s3_sha256 "$archive")"
printf '%s\n' "$digest" > "$archive.sha256"
size="$(wc -c < "$archive" | tr -d ' ')"
count="$(tr -cd '\0' < "$list" | wc -c | tr -d ' ')"
key="$S3_PREFIX/$S3_NAME.tar.gz"

# immutable: the store refuses to replace an existing object (412), so a retry can never
# overwrite what an earlier attempt uploaded. Put the run attempt in the prefix.
put_args=()
[[ "${S3_IMMUTABLE:-false}" == true ]] && put_args=(-H 'If-None-Match: *')
s3_put "$archive" "$key" ${put_args[@]+"${put_args[@]}"}
s3_put "$archive.sha256" "$key.sha256" ${put_args[@]+"${put_args[@]}"}

echo "Uploaded $count files ($size bytes) to s3://$S3_BUCKET/$key (sha256 $digest)"
{
  echo "key=$key"
  echo "sha256=$digest"
  echo "size=$size"
} >> "${GITHUB_OUTPUT:-/dev/null}"
