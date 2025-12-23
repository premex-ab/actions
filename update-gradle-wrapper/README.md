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

### Automated Pull Request

You can configure the action to automatically create a Pull Request when updates are found. This is useful for keeping your repository up-to-date without manual intervention.

```yaml
name: Update Gradle Wrappers
on:
  schedule:
    - cron: '0 0 * * 1'  # Run weekly on Mondays
  workflow_dispatch:

jobs:
  update-gradle-wrappers:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Generate GitHub App token
        uses: actions/create-github-app-token@v2
        id: generate-token
        with:
          app-id: ${{ secrets.APP_ID }}
          private-key: ${{ secrets.APP_PRIVATE_KEY }}

      - name: Update Gradle wrappers
        uses: premex-ab/actions/update-gradle-wrapper@v1
        with:
          create-pr: true
          token: ${{ steps.generate-token.outputs.token }}
```

**Note:** By default, the action uses `github.token` to create the PR. However, PRs created with `GITHUB_TOKEN` will not trigger other workflows (like CI checks). To ensure CI runs on the created PR, it is recommended to use a GitHub App token (as shown above) or a Personal Access Token (PAT).

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `gradle-version` | The Gradle version to update to (e.g., '8.5' or 'latest') | No | `latest` |
| `create-pr` | Whether to create a Pull Request with the changes. If false, changes are left uncommitted for manual handling. | No | `false` |
| `token` | GitHub Token to use for PR creation. Use a GitHub App token or PAT to trigger CI workflows. | No | `github.token` |

## Outputs

| Output | Description |
|--------|-------------|
| `found-count` | Number of Gradle wrappers found in the repository |
| `updated-count` | Number of Gradle wrappers successfully updated |
| `gradle-version` | The actual Gradle version used (resolved from 'latest' if applicable) |
| `updated-paths` | Paths of Gradle wrappers that were successfully updated (newline-separated) |
| `failed-paths` | Paths of Gradle wrappers that failed to update (newline-separated) |

## What it does

1. **Resolves version** - If `gradle-version` is set to 'latest', it fetches the latest Gradle version from the GitHub API
2. **Searches recursively** for `gradlew` executable files in your repository (excluding `.git` directories)
3. **Lists all found wrappers** before starting the update process
4. **Updates each wrapper** by running `./gradlew wrapper --gradle-version <version>` twice in each directory to ensure all files are regenerated
5. **Provides a summary** showing how many wrappers were found and successfully updated
6. **Creates a Pull Request** (if `create-pr: true`) with the changes, using the resolved version in the branch name (e.g., `premex/gradle-wrapper-9.2.1`)
7. **Exits with error code 1** if any wrapper updates fail

## Example output

```
🔄 Resolving 'latest' Gradle version...
✅ Resolved 'latest' to version: 9.2.1
🔍 Searching for Gradle wrapper files (gradlew)...
📦 Found 3 Gradle wrapper(s):
  - ./backend
  - ./frontend
  - ./shared

🚀 Starting Gradle wrapper updates...

📝 Updating wrapper in: /home/runner/work/repo/repo/backend
Downloading https://services.gradle.org/distributions/gradle-9.2.1-bin.zip
...
BUILD SUCCESSFUL in 2s
1 actionable task: 1 executed
BUILD SUCCESSFUL in 657ms
1 actionable task: 1 up-to-date
✅ Successfully updated wrapper in /home/runner/work/repo/repo/backend

📝 Updating wrapper in: /home/runner/work/repo/repo/frontend
BUILD SUCCESSFUL in 1s
1 actionable task: 1 executed
BUILD SUCCESSFUL in 621ms
1 actionable task: 1 up-to-date
✅ Successfully updated wrapper in /home/runner/work/repo/repo/frontend

📝 Updating wrapper in: /home/runner/work/repo/repo/shared
BUILD SUCCESSFUL in 1s
1 actionable task: 1 executed
BUILD SUCCESSFUL in 637ms
1 actionable task: 1 up-to-date
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