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
