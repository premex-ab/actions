#!/usr/bin/env bash
# pass never fails, so `cond && pass || fail` is safe; up/down run through expect.
# shellcheck disable=SC2015,SC2329
# Edge cases from the adversarial review, run directly against the scripts with whatever bash
# runs this file (CI runs it with Apple's /bin/bash 3.2 on macOS). Needs a moto server and:
#   S3_TEST_ENDPOINT, S3_TEST_KEY_ID, S3_TEST_SECRET
set -uo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
upload="$repo/s3-upload-artifact/upload.sh"
download="$repo/s3-download-artifact/download.sh"
work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/s3-edge.XXXXXX")"
export RUNNER_TEMP="$work/tmp" GITHUB_OUTPUT=/dev/null
mkdir -p "$RUNNER_TEMP"
export S3_ENDPOINT="$S3_TEST_ENDPOINT" S3_BUCKET=ci-artifacts S3_ACCESS_KEY_ID="$S3_TEST_KEY_ID" \
  S3_SECRET_ACCESS_KEY="$S3_TEST_SECRET" S3_PREFIX="edge/$$" S3_IF_NO_FILES_FOUND=error
failures=0
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }
# expect <ok|fail> <description> <command...>: the command's output lands in $out.
expect() {
  local want="$1" what="$2"; shift 2
  if out="$("$@" 2>&1)"; then got=ok; else got=fail; fi
  if [[ "$got" == "$want" ]]; then pass "$what"; else fail "$what (wanted $want, got $got): $out"; fi
}
up() { (cd "$1" && S3_NAME="$2" S3_PATH="$3" "$BASH" "$upload"); }
down() { S3_NAME="$1" S3_DESTINATION="$2" "$BASH" "$download"; }
# upx <dir> VAR=value...: upload from <dir> with extra environment. downx VAR=value...: download.
upx() { local dir="$1"; shift; (cd "$dir" && env "$@" "$BASH" "$upload"); }
downx() { env "$@" "$BASH" "$download"; }

echo "bash $BASH_VERSION, $(tar --version | head -n 1), $(curl --version | head -n 1 | cut -d' ' -f1-2)"

# Hidden files stay out unless asked for.
src="$work/hidden"; mkdir -p "$src/.git" "$src/app"
echo token > "$src/.git/config"; echo data > "$src/app/file"; echo env > "$src/app/.env"
expect ok "upload '*' without hidden files" up "$src" hidden '*'
expect ok "download it" down hidden "$work/hidden-out"
[[ -e "$work/hidden-out/app/file" && ! -e "$work/hidden-out/.git/config" && ! -e "$work/hidden-out/app/.env" ]] \
  && pass "hidden files left out by default" || fail "hidden files left out by default: $(cd "$work/hidden-out" && find . -type f)"
expect ok "upload with include-hidden-files" upx "$src" S3_INCLUDE_HIDDEN_FILES=true S3_NAME=hidden2 S3_PATH=app
expect ok "download it" down hidden2 "$work/hidden2-out"
[[ -e "$work/hidden2-out/app/.env" ]] && pass "hidden files included on request" || fail "hidden files included on request"

# '.*' must never reach the parent directory, whatever the bash version.
mkdir -p "$work/parent/child"; echo secret > "$work/parent/secret.txt"; echo mine > "$work/parent/child/.mine"
expect ok "upload '.*' with hidden files" upx "$work/parent/child" S3_INCLUDE_HIDDEN_FILES=true S3_NAME=dots 'S3_PATH=.*'
expect ok "download it" down dots "$work/dots-out"
[[ -e "$work/dots-out/.mine" && -z "$(find "$work/dots-out" -name secret.txt)" ]] \
  && pass "'.*' stays inside the working directory" || fail "'.*' stays inside the working directory: $(cd "$work/dots-out" && find . -type f)"

# A symlinked directory is stored as real files, even when also matched through a glob.
mkdir -p "$work/links/real/d"; echo aab > "$work/links/real/d/app.aab"; ln -s real/d "$work/links/out"
expect ok "upload a symlinked directory" up "$work/links" linked $'out\nout/*.aab'
expect ok "download it" down linked "$work/linked-out"
[[ -f "$work/linked-out/out/app.aab" && ! -L "$work/linked-out/out" ]] \
  && pass "symlinked directory arrives as files" || fail "symlinked directory arrives as files"

# File names starting with '-' are files, not tar options.
mkdir -p "$work/dash"; echo x > "$work/dash/--checkpoint-action=exec=touch pwned"; echo y > "$work/dash/-C"
expect ok "upload names starting with '-'" up "$work/dash" dash '*'
expect ok "download it" down dash "$work/dash-out"
[[ -e "$work/dash-out/-C" && ! -e "$work/dash/pwned" && ! -e pwned ]] \
  && pass "dash-named files archived as files" || fail "dash-named files archived as files"

# Paths with spaces, and ** only where bash supports it.
mkdir -p "$work/sp/a b/c"; echo z > "$work/sp/a b/c/f.txt"
expect ok "upload a path with spaces" up "$work/sp" spaces 'a b'
if (( BASH_VERSINFO[0] >= 4 )); then
  expect ok "** recurses on bash 4+" up "$work/sp" globstar '**/*.txt'
else
  expect fail "** refused on bash 3.2" up "$work/sp" globstar '**/*.txt'
  grep -q "needs bash 4" <<< "$out" && pass "** refusal says why" || fail "** refusal says why: $out"
fi

# Input validation.
expect fail "name with a slash is refused" up "$work/sp" 'a/b' 'a b'
expect fail "absolute path is refused" up "$work/sp" abs /etc/hosts
expect fail "'..' path is refused" up "$work/sp" dotdot '../x'
expect fail "secret with a newline is refused" upx "$work/sp" S3_SECRET_ACCESS_KEY=$'x\noutput = /tmp/pwned' S3_NAME=nl 'S3_PATH=a b'
grep -q "control character" <<< "$out" && pass "newline refusal says why" || fail "newline refusal says why: $out"
expect fail "wrong secret is refused" downx S3_SECRET_ACCESS_KEY=wrong S3_NAME=spaces S3_DESTINATION="$work/nope"
grep -q "SignatureDoesNotMatch" <<< "$out" && pass "the S3 error code is shown" || fail "the S3 error code is shown: $out"

# Pinned checksum.
digest="$(cd "$work/sp" && S3_NAME=pinned S3_PATH='a b' GITHUB_OUTPUT="$work/pinned.out" "$BASH" "$upload" > /dev/null && sed -n 's/^sha256=//p' "$work/pinned.out")"
expect ok "download with the right pinned sha256" downx S3_EXPECTED_SHA256="$digest" S3_NAME=pinned S3_DESTINATION="$work/pin-ok"
expect fail "download with a wrong pinned sha256" downx S3_EXPECTED_SHA256="$(printf '0%.0s' {1..64})" S3_NAME=pinned S3_DESTINATION="$work/pin-bad"
[[ ! -e "$work/pin-bad/a b" ]] && pass "nothing unpacked on a pinned mismatch" || fail "nothing unpacked on a pinned mismatch"

# A planted archive with a symlink and a matching .sha256 is refused before unpacking.
mkdir -p "$work/evil"; ln -s /etc/passwd "$work/evil/gradlew"
(cd "$work/evil" && tar -czf "$work/evil.tar.gz" gradlew)
python3 "$repo/.github/s3-test/tamper.py" "$S3_PREFIX/evil.tar.gz" "$work/evil.tar.gz"
printf '%s\n' "$(if command -v sha256sum > /dev/null; then sha256sum "$work/evil.tar.gz"; else shasum -a 256 "$work/evil.tar.gz"; fi | cut -d' ' -f1)" > "$work/evil.sha256"
python3 "$repo/.github/s3-test/tamper.py" "$S3_PREFIX/evil.tar.gz.sha256" "$work/evil.sha256"
expect fail "planted archive with a symlink is refused" down evil "$work/evil-out"
[[ ! -e "$work/evil-out/gradlew" ]] && pass "nothing unpacked from the planted archive" || fail "nothing unpacked from the planted archive"

# A half-finished pair reads as such.
python3 "$repo/.github/s3-test/tamper.py" "$S3_PREFIX/spaces.tar.gz.sha256"
expect fail "archive and .sha256 out of step" down spaces "$work/pair"
grep -q "failed halfway" <<< "$out" && pass "out-of-step pair says why" || fail "out-of-step pair says why: $out"

# immutable: a second upload under the same key is refused; without it, it overwrites.
mkdir -p "$work/imm"; echo one > "$work/imm/f"
expect ok "immutable first upload" upx "$work/imm" S3_IMMUTABLE=true S3_NAME=immutable S3_PATH=f
echo two > "$work/imm/f"
expect fail "immutable second upload is refused" upx "$work/imm" S3_IMMUTABLE=true S3_NAME=immutable S3_PATH=f
grep -q "PreconditionFailed" <<< "$out" && pass "refusal names the precondition" || fail "refusal names the precondition: $out"
expect ok "download still gets the first upload" down immutable "$work/imm-out"
[[ "$(cat "$work/imm-out/f")" == one ]] && pass "first upload kept" || fail "first upload kept: $(cat "$work/imm-out/f")"
expect ok "non-immutable upload overwrites" upx "$work/imm" S3_NAME=immutable S3_PATH=f

echo "$failures failure(s)"
exit $((failures > 0))
