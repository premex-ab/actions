# Update Gradle Wrapper Action

This GitHub Action recursively finds and updates Gradle wrappers in your repository to the latest version (or a specified version).

## Usage

### Basic usage (updates to latest Gradle version)

```yaml
name: Update Gradle Wrappers
on:
  schedule:
    - cron: '0 0 * * 1'  # Run weekly on Mondays
  workflow_dispatch:     # Allow manual trigger

jobs:
  update-gradle-wrappers:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        
      - name: Update Gradle wrappers
        uses: premex-ab/actions/update-gradle-wrapper@v1
```

### Specify a specific Gradle version

```yaml
- name: Update Gradle wrappers
  uses: premex-ab/actions/update-gradle-wrapper@v1
  with:
    gradle-version: '8.5'
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `gradle-version` | The Gradle version to update to | No | `latest` |

## Outputs

| Output | Description |
|--------|-------------|
| `found-count` | Number of Gradle wrappers found in the repository |
| `updated-count` | Number of Gradle wrappers successfully updated |

## What it does

1. **Searches recursively** for `gradlew` executable files in your repository (excluding `.git` directories)
2. **Lists all found wrappers** before starting the update process
3. **Updates each wrapper** by running `./gradlew wrapper --gradle-version <version>` in each directory containing a `gradlew` file
4. **Provides a summary** showing how many wrappers were found and successfully updated
5. **Exits with error code 1** if any wrapper updates fail

## Example output

```
🔍 Searching for Gradle wrapper files (gradlew)...
📦 Found 3 Gradle wrapper(s):
  - ./backend
  - ./frontend
  - ./shared

🚀 Starting Gradle wrapper updates...

📝 Updating wrapper in: /home/runner/work/repo/repo/backend
BUILD SUCCESSFUL in 2s
1 actionable task: 1 executed
✅ Successfully updated wrapper in /home/runner/work/repo/repo/backend

📝 Updating wrapper in: /home/runner/work/repo/repo/frontend
BUILD SUCCESSFUL in 1s
1 actionable task: 1 executed
✅ Successfully updated wrapper in /home/runner/work/repo/repo/frontend

📝 Updating wrapper in: /home/runner/work/repo/repo/shared
BUILD SUCCESSFUL in 1s
1 actionable task: 1 executed
✅ Successfully updated wrapper in /home/runner/work/repo/repo/shared

📊 Update Summary:
  - Found: 3 wrapper(s)
  - Updated: 3 wrapper(s)
  - Failed: 0 wrapper(s)

🎉 All Gradle wrappers updated successfully!
```

## Requirements

- The repository must have Java available (typically handled by using `actions/setup-java` before this action)
- Each directory with a `gradlew` file should be a valid Gradle project

## License

MIT License - see [LICENSE](../LICENSE) file for details.