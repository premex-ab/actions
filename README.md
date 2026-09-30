# actions
Internal actions for the premex organization

## Available Actions

### Update Gradle Wrapper
Automatically updates Gradle wrappers in repositories to the latest version (or a specified version).

```yaml
- uses: premex-ab/actions/update-gradle-wrapper@v1
  with:
    gradle-version: 'latest'  # optional, defaults to 'latest'
```

For detailed documentation, see [update-gradle-wrapper/README.md](update-gradle-wrapper/README.md).

### S3 Upload / Download Artifact
Store workflow artifacts in any S3-compatible bucket instead of GitHub's artifact storage. The
download checks a SHA-256 before unpacking. Works on self-hosted macOS and Linux runners.

```yaml
- uses: premex-ab/actions/s3-upload-artifact@v1
  with:
    name: my-bundle
    path: build/outputs/*.aab
    endpoint: ${{ vars.ARTIFACT_S3_ENDPOINT }}
    bucket: ${{ vars.ARTIFACT_S3_BUCKET }}
    access-key-id: ${{ secrets.ARTIFACT_S3_ACCESS_KEY_ID }}
    secret-access-key: ${{ secrets.ARTIFACT_S3_SECRET_ACCESS_KEY }}
```

For detailed documentation, see [s3-upload-artifact/README.md](s3-upload-artifact/README.md).

## Releases and Versioning

This repository uses semantic versioning with moveable major version tags:

- **Specific versions**: Use `@v1.2.3` to pin to an exact release
- **Major versions**: Use `@v1` to automatically get the latest v1.x.y release

When a new release is created (e.g., `v1.2.3`), the release workflow automatically updates the corresponding major version tag (`v1`) to point to the new release.

Merges to `main` release automatically. The **Publish Release** workflow (`publish-release.yml`) picks the next version, creates the release with generated notes and moves the major version tag:

- **No release** when only tests, docs, `.github` or the test projects changed.
- **Patch** (`v1.2.3` → `v1.2.4`) when an action changed.
- **Minor** (`v1.2.3` → `v1.3.0`) when a new action was added.
- **A `minor` or `major` label** on a merged pull request raises the bump. Use `major` for breaking changes.

To publish a specific version, run the workflow by hand with that version. This allows consuming actions with major version references that automatically receive compatible updates.

### Example Usage

```yaml
# Always get the latest v1.x.y release
- uses: premex-ab/actions/update-gradle-wrapper@v1

# Pin to a specific version
- uses: premex-ab/actions/update-gradle-wrapper@v1.2.3
```
