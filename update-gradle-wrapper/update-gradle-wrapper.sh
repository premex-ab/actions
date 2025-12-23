#!/bin/bash

# Use pipefail but handle errors manually in gradlew calls
set -uo pipefail

# Get the Gradle version from input (default to 'latest')
GRADLE_VERSION="${1:-latest}"

# Resolve 'latest' to actual latest version
if [ "$GRADLE_VERSION" = "latest" ]; then
    echo "🔄 Resolving 'latest' Gradle version..."
    # Get the latest version from Gradle releases API
    LATEST_VERSION=$(curl -s https://api.github.com/repos/gradle/gradle/releases/latest | grep '"tag_name"' | cut -d '"' -f 4 | sed 's/^v//')
    if [ -n "$LATEST_VERSION" ]; then
        GRADLE_VERSION="$LATEST_VERSION"
        echo "✅ Resolved 'latest' to version: $GRADLE_VERSION"
    else
        echo "⚠️  Failed to resolve 'latest' version, using 8.5 as fallback"
        GRADLE_VERSION="8.5"
    fi
fi

echo "🔍 Searching for Gradle wrapper files (gradlew)..."

# Find all gradlew files recursively, excluding .git directories
GRADLEW_PATHS=()
while IFS= read -r -d '' file; do
    GRADLEW_PATHS+=("$file")
done < <(find . -name "gradlew" -type f -not -path "*/.git/*" -print0)

FOUND_COUNT=${#GRADLEW_PATHS[@]}
UPDATED_COUNT=0
FAILED_PATHS=()
UPDATED_PATHS=()

echo "📦 Found $FOUND_COUNT Gradle wrapper(s):"
for gradlew_path in "${GRADLEW_PATHS[@]}"; do
    wrapper_dir=$(dirname "$gradlew_path")
    echo "  - $wrapper_dir"
done

if [ "$FOUND_COUNT" -eq 0 ]; then
    echo "ℹ️  No Gradle wrappers found in the repository."
    echo "found-count=0" >> "$GITHUB_OUTPUT"
    echo "updated-count=0" >> "$GITHUB_OUTPUT"
    exit 0
fi

echo ""
echo "🚀 Starting Gradle wrapper updates..."
echo ""

# Store the original directory
ORIGINAL_DIR=$(pwd)

# Update each wrapper
for gradlew_path in "${GRADLEW_PATHS[@]}"; do
    wrapper_dir=$(dirname "$gradlew_path")
    wrapper_abs_dir=$(cd "$wrapper_dir" && pwd)
    echo "📝 Updating wrapper in: $wrapper_abs_dir"
    
    # Change to the directory containing gradlew
    if cd "$wrapper_abs_dir"; then
        # Make gradlew executable if it isn't already
        chmod +x "./gradlew"
        
        # Update the wrapper (run twice to ensure all files are updated)
        # First run: Updates gradle-wrapper.properties
        # Second run: Uses new version to regenerate jar and scripts
        if ./gradlew wrapper --gradle-version "$GRADLE_VERSION" && \
           ./gradlew wrapper; then
            echo "✅ Successfully updated wrapper in $wrapper_abs_dir"
            ((UPDATED_COUNT++))
            UPDATED_PATHS+=("$wrapper_abs_dir")
        else
            echo "❌ Failed to update wrapper in $wrapper_abs_dir"
            FAILED_PATHS+=("$wrapper_abs_dir")
        fi
        
        # Return to the original directory
        cd "$ORIGINAL_DIR" || exit
    else
        echo "❌ Failed to change to directory $wrapper_abs_dir"
        FAILED_PATHS+=("$wrapper_abs_dir")
    fi
    
    echo ""
done

# Print summary
echo "📊 Update Summary:"
echo "  - Found: $FOUND_COUNT wrapper(s)"
echo "  - Updated: $UPDATED_COUNT wrapper(s)"
echo "  - Failed: $((FOUND_COUNT - UPDATED_COUNT)) wrapper(s)"

if [ ${#FAILED_PATHS[@]} -gt 0 ]; then
    echo ""
    echo "❌ Failed updates:"
    for failed_path in "${FAILED_PATHS[@]}"; do
        echo "  - $failed_path"
    done
fi

# Set outputs for GitHub Actions
{
    echo "found-count=$FOUND_COUNT"
    echo "updated-count=$UPDATED_COUNT"
    echo "gradle-version=$GRADLE_VERSION"

    # Output paths as newline-separated strings using proper multiline format
    echo "updated-paths<<EOF"
    if [ ${#UPDATED_PATHS[@]} -gt 0 ]; then
        printf "%s\n" "${UPDATED_PATHS[@]}"
    fi
    echo "EOF"
    
    echo "failed-paths<<EOF"
    if [ ${#FAILED_PATHS[@]} -gt 0 ]; then
        printf "%s\n" "${FAILED_PATHS[@]}"
    fi
    echo "EOF"
} >> "$GITHUB_OUTPUT"

# Exit with error if any updates failed
if [ "$UPDATED_COUNT" -lt "$FOUND_COUNT" ]; then
    echo ""
    echo "⚠️  Some Gradle wrapper updates failed. Please check the logs above."
    exit 1
else
    echo ""
    echo "🎉 All Gradle wrappers updated successfully!"
    exit 0
fi