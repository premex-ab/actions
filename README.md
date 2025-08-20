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

## Releases and Versioning

This repository uses semantic versioning with moveable major version tags:

- **Specific versions**: Use `@v1.2.3` to pin to an exact release
- **Major versions**: Use `@v1` to automatically get the latest v1.x.y release

When a new release is created (e.g., `v1.2.3`), the release workflow automatically updates the corresponding major version tag (`v1`) to point to the new release. This allows consuming actions with major version references that automatically receive compatible updates.

### Example Usage

```yaml
# Always get the latest v1.x.y release
- uses: premex-ab/actions/update-gradle-wrapper@v1

# Pin to a specific version
- uses: premex-ab/actions/update-gradle-wrapper@v1.2.3
```
