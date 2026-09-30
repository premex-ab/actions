# S3 Upload Artifact / S3 Download Artifact

A replacement for `actions/upload-artifact` and `actions/download-artifact` backed by any
S3-compatible bucket (MinIO, Garage, Ceph RGW, SeaweedFS, AWS S3, …) instead of GitHub's
artifact storage. Use it when:

- GitHub artifact storage is full or too small, or
- the runners sit next to a bucket on the same network, where transfers are much faster.

Both actions are plain `bash` composite actions using `curl --aws-sigv4`. They need no AWS CLI and
no Docker, so they run on self-hosted macOS runners (including Apple's `/bin/bash` 3.2) as well as
on Linux.

## How it works

- **Upload** packs the matching paths into one `<name>.tar.gz`, keeping each path relative to
  `working-directory`, and stores it at `<prefix>/<name>.tar.gz` with its SHA-256 in
  `<prefix>/<name>.tar.gz.sha256`.
- **Download** fetches both objects, refuses the archive unless the SHA-256 matches, then unpacks
  it, so the original layout is recreated under `path`.
- **The default prefix** is `<owner>/<repo>/<run id>`. Jobs of the same workflow run share it,
  which is what handing a file from a build job to a publish job needs. Re-running a job
  overwrites its artifact.

## Usage

```yaml
jobs:
  build:
    runs-on: tart
    steps:
      # ... build app-release.aab ...
      - uses: premex-ab/actions/s3-upload-artifact@v1
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
| `endpoint` | yes | | `scheme://host[:port]`. Path-style addressing is used. |
| `bucket` | yes | | Bucket name |
| `region` | no | `us-east-1` | Signing region. Many self-hosted stores accept any value. |
| `access-key-id` | yes | | From a secret |
| `secret-access-key` | yes | | From a secret |
| `ca-certificate` | no | | PEM of an internal CA, when the endpoint's TLS certificate is not publicly trusted |
| `prefix` | no | `<owner>/<repo>/<run id>` | Key prefix |

Upload only:

| Input | Default | Description |
| --- | --- | --- |
| `path` | | Files, directories or globs, one per line, relative to `working-directory`. `**` needs bash 4; with Apple's bash 3.2 it matches like `*`. Directories are included recursively. |
| `working-directory` | `.` | Directory the paths are relative to |
| `if-no-files-found` | `error` | `error`, `warn` or `ignore` |

Download only:

| Input | Default | Description |
| --- | --- | --- |
| `path` | `.` | Directory to unpack into |

Outputs: `key` and `sha256` from both actions, `size` from upload, `download-path` from download.

## Setting up a bucket

Ask the bucket's owner for:

- **Endpoint URL**: scheme, host and port, reachable from the runners.
- **TLS**: a public certificate, or the internal CA's certificate to pass as `ca-certificate`.
- **Bucket name and region.**
- **An access key limited to that bucket** (or a prefix), with read, write and list.
- **An expiry (lifecycle) rule** that deletes objects after a few days. The actions never delete
  anything, so without one the bucket grows forever.

Store the key pair as secrets and the endpoint, bucket and region as variables, scoped to the
environment of the jobs that use them.
