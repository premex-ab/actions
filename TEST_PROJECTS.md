# Test Gradle Projects

This directory contains test Gradle projects with different outdated wrapper versions to test the `update-gradle-wrapper` action.

## Test Projects

- **test-gradle-project-1**: Uses Gradle 7.6
- **test-gradle-project-2**: Uses Gradle 7.3.3 (Java 17+ compatible)
- **test-gradle-project-3**: Uses Gradle 8.0

## Testing the Action

Use the `test-update-gradle-wrapper.yml` workflow to manually test the update action:

1. Go to the Actions tab in GitHub
2. Select "Test Update Gradle Wrapper Action"
3. Click "Run workflow"
4. Optionally specify a Gradle version (defaults to 'latest')
5. Monitor the workflow to see the action in operation

The workflow will:
1. Display current wrapper versions
2. Run the update-gradle-wrapper action
3. Show the results (found/updated counts)
4. Display the new wrapper versions
5. Test that the updated wrappers work correctly

## Manual Testing

You can also test the action locally by running:

```bash
./update-gradle-wrapper/update-gradle-wrapper.sh
```

This will find and update all Gradle wrappers in the repository to the latest version.