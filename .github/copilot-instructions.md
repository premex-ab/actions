# GitHub Actions Repository

This repository contains internal GitHub Actions for the premex organization. These actions can be JavaScript/TypeScript (Node.js), shell-based composite actions, or Docker-based actions.

**ALWAYS follow these instructions first** - only fallback to additional search and context gathering if the information here is incomplete or found to be in error.

## Working Effectively

### Repository Setup and Dependencies
- Bootstrap the repository:
  ```bash
  cd /path/to/actions
  git clone <repo-url> .
  ```
- Install system dependencies that may be needed:
  ```bash
  # Essential tools for GitHub Actions development (most already available)
  which node npm docker git curl jq yamllint shellcheck
  ```
- Install act for local testing:
  ```bash
  curl -s https://api.github.com/repos/nektos/act/releases/latest \
    | grep "browser_download_url.*act_Linux_x86_64.tar.gz" \
    | cut -d '"' -f 4 | xargs wget -q -O - | tar -xzf - -C /tmp
  sudo mv /tmp/act /usr/local/bin/act
  act --version
  ```
- Configure act for consistent behavior:
  ```bash
  mkdir -p ~/.config/act
  echo "-P ubuntu-latest=catthehacker/ubuntu:act-latest" > ~/.config/act/actrc
  ```

### Building and Testing Actions

#### JavaScript/TypeScript Actions
- For Node.js-based actions (e.g., `hello-world/`):
  ```bash
  cd hello-world
  npm install                    # Takes 5-10 seconds. NEVER CANCEL.
  ```
- **NEVER CANCEL** Node.js dependency installation - set timeout to 5+ minutes for safety.

#### Docker Actions
- For Docker-based actions (e.g., `docker-hello/`):
  ```bash
  cd docker-hello
  time docker build -t test-action .  # Takes 1-3 minutes. NEVER CANCEL.
  ```
- **NEVER CANCEL** Docker builds - set timeout to 10+ minutes for safety.
- Test Docker action manually:
  ```bash
  docker run --rm test-action "Test Input"
  ```

#### Shell Composite Actions
- Shell actions (e.g., `shell-hello/`) require no build step
- Validate with yamllint (see Validation section)

### Local Testing with Act

#### Basic Act Usage
- List available workflows:
  ```bash
  act -l
  ```
- Run workflows locally (dry run first):
  ```bash
  act push --dryrun              # Takes 30-60 seconds. NEVER CANCEL.
  act push -j job-name           # Takes 1-5 minutes. NEVER CANCEL.
  ```
- **NEVER CANCEL** act runs - they may take several minutes to complete, especially on first run when pulling Docker images.

#### Act Limitations in Some Environments
- Act may fail with Docker/container issues in some restricted environments
- Certificate issues may prevent downloading some dependencies in act
- In such cases, rely on GitHub's actual workflow runs for full validation

### Validation

#### YAML Validation
- **ALWAYS** validate YAML files before committing:
  ```bash
  yamllint .github/workflows/*.yml     # Takes <5 seconds
  yamllint */action.yml                # Takes <5 seconds
  ```
- Fix common yamllint issues:
  - Add `---` document start
  - Use `'on':` instead of `on:` to avoid truthy warnings
  - Remove trailing spaces
  - Ensure newline at end of file

#### Shell Script Validation
- For any shell scripts:
  ```bash
  shellcheck *.sh */entrypoint.sh     # Takes <5 seconds
  ```

#### Action Structure Validation
- Ensure action.yml files have required fields:
  - `name`: Action name
  - `description`: Action description  
  - `inputs`: Input definitions (optional)
  - `outputs`: Output definitions (optional)
  - `runs`: Execution configuration

### Repository Structure and Navigation

#### Current Repository Contents
```
.
├── .github/
│   └── workflows/
│       ├── test.yml              # Tests Node.js action
│       └── test-shell.yml        # Tests shell action
├── hello-world/                  # Example Node.js action
│   ├── action.yml               # Action definition
│   ├── index.js                 # Main JavaScript file
│   ├── package.json             # Node.js dependencies
│   └── node_modules/            # Dependencies (gitignored)
├── shell-hello/                  # Example shell composite action
│   └── action.yml               # Action definition
├── docker-hello/                 # Example Docker action
│   ├── action.yml               # Action definition
│   ├── Dockerfile               # Container definition
│   └── entrypoint.sh            # Entry script
├── .gitignore                    # Excludes node_modules, build artifacts
├── README.md                     # Basic repository description
└── LICENSE                       # MIT license
```

#### Key Locations
- **Action definitions**: `*/action.yml` - Core action metadata and configuration
- **Workflows**: `.github/workflows/*.yml` - Test and validation workflows
- **Node.js actions**: Look for `package.json`, `index.js`, `lib/` directories
- **Docker actions**: Look for `Dockerfile`, `entrypoint.sh`
- **Shell actions**: Composite actions using `runs.using: composite`

### Creating New Actions

#### Create a New JavaScript Action
```bash
mkdir my-new-action
cd my-new-action

# Create action.yml
cat > action.yml << 'EOF'
---
name: 'My New Action'
description: 'Description of what this action does'
inputs:
  example-input:
    description: 'Example input description'
    required: true
    default: 'default-value'
outputs:
  example-output:
    description: 'Example output description'
runs:
  using: 'node20'
  main: 'index.js'
EOF

# Create package.json
npm init -y
npm install @actions/core @actions/github

# Create index.js
cat > index.js << 'EOF'
const core = require('@actions/core');
const github = require('@actions/github');

try {
  const inputValue = core.getInput('example-input');
  console.log(`Processing input: ${inputValue}`);
  
  // Your action logic here
  
  core.setOutput('example-output', 'result-value');
} catch (error) {
  core.setFailed(error.message);
}
EOF
```

#### Create a New Docker Action
```bash
mkdir my-docker-action
cd my-docker-action

# Create action.yml
cat > action.yml << 'EOF'
---
name: 'My Docker Action'
description: 'Description of what this action does'
inputs:
  example-input:
    description: 'Example input description'
    required: true
runs:
  using: 'docker'
  image: 'Dockerfile'
  args:
    - ${{ inputs.example-input }}
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM alpine:3.18
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
EOF

# Create entrypoint.sh
cat > entrypoint.sh << 'EOF'
#!/bin/sh -l
echo "Processing input: $1"
# Your action logic here
echo "output-name=result-value" >> $GITHUB_OUTPUT
EOF

chmod +x entrypoint.sh
```

### Common Tasks and Time Expectations

#### Timing and Timeout Guidelines
- **Node.js `npm install`**: 5-30 seconds - set timeout to 5+ minutes
- **Docker build**: 1-5 minutes - set timeout to 10+ minutes  
- **Act dry run**: 30-60 seconds - set timeout to 5+ minutes
- **Act full run**: 1-5 minutes - set timeout to 10+ minutes
- **YAML validation**: <5 seconds - set timeout to 1+ minute
- **Shell validation**: <5 seconds - set timeout to 1+ minute

#### Pre-commit Validation Checklist
Always run these commands before committing changes:
```bash
# 1. Validate YAML syntax
yamllint .github/workflows/*.yml */action.yml

# 2. Validate shell scripts if any
find . -name "*.sh" -exec shellcheck {} \;

# 3. Test locally if possible
act push --dryrun

# 4. For Node.js actions, ensure dependencies are installed
find . -name "package.json" -not -path "*/node_modules/*" \
  -exec bash -c 'cd "$(dirname "$1")" && npm install' _ {} \;
```

### Troubleshooting

#### Common Issues
- **Act certificate errors**: Expected in restricted environments - validate through GitHub instead
- **Docker permissions**: Ensure Docker daemon is running and user has permissions
- **Node.js version mismatches**: GitHub Actions uses Node.js 20, ensure compatibility
- **YAML syntax errors**: Use yamllint to identify and fix formatting issues

#### When Commands Don't Work
- **`npm install` fails**: Check network connectivity, try `npm install --verbose`
- **Docker build fails**: Check Dockerfile syntax, ensure base image is accessible
- **Act fails to run**: Check Docker setup, try `act --version` to verify installation

### CI/CD Integration
- Actions are automatically tested when pushed to GitHub
- Local validation with act provides quick feedback but may not catch all issues
- Always test in actual GitHub Actions environment for final validation
- Consider adding workflow dispatch triggers for manual testing

### Important Notes
- **NEVER CANCEL** long-running commands - builds may take several minutes
- Always set generous timeouts (5-10+ minutes) for build operations
- Test actions both locally and in GitHub environment
- Use semantic versioning for action releases
- Document breaking changes in action descriptions
- Keep actions focused and single-purpose