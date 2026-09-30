# S3 Upload Artifact / S3 Download Artifact

These actions do the job of `actions/upload-artifact` and `actions/download-artifact`, but store
artifacts in any S3-compatible bucket (MinIO, Garage, Ceph RGW, SeaweedFS, AWS S3, …) instead of
GitHub's artifact storage. Use them when:

- GitHub artifact storage is full or too small, or
- the runners sit next to a bucket on the same network, where transfers are much faster.

Both are plain `bash` composite actions using `curl --aws-sigv4`. They need no AWS CLI and no
Docker, so they run on self-hosted macOS runners (including Apple's `/bin/bash` 3.2) as well as on
Linux. Windows runners are not supported.

## How it works

- **Upload** packs the matching files into one `<name>.tar.gz`, keeping each path relative to
  `working-directory`. It stores the archive at `<prefix>/<name>.tar.gz` and its SHA-256 at
  `<prefix>/<name>.tar.gz.sha256`, and returns the SHA-256 as the `sha256` output.
  - **Symbolic links are followed:** the archive holds regular files only.
  - **Hidden files are left out** unless `include-hidden-files: true`. A name starting with `.`
    includes `.git`, whose `config` holds the checkout token.
- **Download** fetches the archive and checks its SHA-256 (see *Integrity* below).
  - It refuses archives that contain links, special files, absolute paths or `..`.
  - Only then does it unpack, recreating the original layout under `path`.
- **The default prefix** is `<owner>/<repo>/<run id>`.
  - Jobs of the same workflow run share it, which is what handing a file from a build job to a
    publish job needs.
  - Re-running a job overwrites its artifact.
  - Two jobs that upload the same name at the same time (a matrix, say) overwrite each other. Give
    each its own name.

## Integrity

**The `.sha256` in the bucket catches corruption and half-finished uploads.** It does not stop
anyone who can write to the bucket: they can replace the archive and its `.sha256` together.

**To also rule that out, pin the checksum.** Pass the upload's `sha256` output to the downloading
job through job outputs. That channel goes through GitHub, not the bucket. The download then
refuses any archive that doesn't match it.

**Unpack into a fresh directory** (`path: some-new-dir`), not the workspace. Then an artifact can
never overwrite scripts the job runs afterwards.

## Usage

```yaml
jobs:
  build:
    runs-on: tart
    outputs:
      bundle-sha256: ${{ steps.bundle.outputs.sha256 }}
    steps:
      # ... build app-release.aab ...
      - id: bundle
        uses: premex-ab/actions/s3-upload-artifact@v1
        with:
          name: tandayo-play-${{ inputs.version_code }}
          path: |
            android/app/build/outputs/bundle/release/*.aab
            android/app/build/outputs/bundle/release/*.sha256
          endpoint: ${{ vars.ARTIFACT_S3_ENDPOINT }}
          bucket: ${{ vars.ARTIFACT_S3_BUCKET }}
          region: ${{ vars.ARTIFACT_S3_REGION }}
          access-key-id: ${{ secrets.ARTIFACT_S3_ACCESS_KEY_ID }}
          secret-access-key: ${{ secrets.ARTIFACT_S3_SECRET_ACCESS_KEY }}

  publish:
    needs: build
    runs-on: tart
    steps:
      - uses: premex-ab/actions/s3-download-artifact@v1
        with:
          name: tandayo-play-${{ inputs.version_code }}
          path: release-artifact
          sha256: ${{ needs.build.outputs.bundle-sha256 }}
          endpoint: ${{ vars.ARTIFACT_S3_ENDPOINT }}
          bucket: ${{ vars.ARTIFACT_S3_BUCKET }}
          region: ${{ vars.ARTIFACT_S3_REGION }}
          access-key-id: ${{ secrets.ARTIFACT_S3_ACCESS_KEY_ID }}
          secret-access-key: ${{ secrets.ARTIFACT_S3_SECRET_ACCESS_KEY }}
```

## Inputs

Shared by both actions:

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `name` | yes | | Artifact name: letters, digits, `.`, `_`, `-` |
| `endpoint` | yes | | `scheme://host[:port]`. Path-style addressing is used. Plain `http` works but warns: bodies are not covered by the signature. |
| `bucket` | yes | | Bucket name |
| `region` | no | `us-east-1` | Signing region. Many self-hosted stores accept any value. |
| `access-key-id` | yes | | From a secret |
| `secret-access-key` | yes | | From a secret |
| `ca-certificate` | no | | PEM of an internal CA, when the endpoint's TLS certificate is not publicly trusted |
| `prefix` | no | `<owner>/<repo>/<run id>` | Key prefix |

Upload only:

| Input | Default | Description |
| --- | --- | --- |
| `path` | | Files, directories or globs, one per line, relative to `working-directory`. Directories are included recursively. `**` needs bash 4 or later; with Apple's bash 3.2 the upload fails and says so. `!` exclusions are not supported. |
| `working-directory` | `.` | Directory the paths are relative to |
| `include-hidden-files` | `false` | Include files and directories whose name starts with `.` |
| `if-no-files-found` | `error` | `error`, `warn` or `ignore` |

Download only:

| Input | Default | Description |
| --- | --- | --- |
| `path` | `.` | Directory to unpack into. Prefer a fresh one. |
| `sha256` | | Expected SHA-256, from the upload's `sha256` output (see *Integrity*) |

Outputs: `key` and `sha256` from both actions, `size` from upload, `download-path` from download.

## Requirements and limits

- **curl 7.76 or later.** Tested with curl 8; the actions check the version.
- **One archive is one PUT.** AWS S3 and Ceph RGW cap a single PUT at 5 GB by default.
- **Stalled transfers are aborted.** A transfer that stays below 1 KiB/s for a minute fails
  instead of hanging the job.
- **Failures show the store's error code and message**, for example `SignatureDoesNotMatch`.

## Setting up a bucket

Ask the bucket's owner for:

- **Endpoint URL**: scheme, host and port, reachable from the runners.
- **TLS**: a public certificate, or the internal CA's certificate to pass as `ca-certificate`.
- **Bucket name and region.**
- **An access key limited to that bucket** (better: to one prefix per repository), allowed to read
  and write objects. The actions never list or delete.
- **An expiry (lifecycle) rule** that deletes objects after a few days. Without one the bucket
  grows forever.

Store the key pair as secrets and the endpoint, bucket and region as variables, scoped to the
environment of the jobs that use them.
