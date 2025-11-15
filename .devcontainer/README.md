# SamplerDome Development Container

This devcontainer provides a Julia development environment for the SamplerDome project.

## What's Included

- **Julia 1.10.7** - Latest stable version
- **Pre-installed packages**: Distributions, Random, Logging
- **VS Code Julia extension** - Syntax highlighting, REPL, debugging
- **Git & GitHub CLI** - Version control tools
- **Build tools** - gcc, make, and other essentials

## How to Use

### First Time Setup

1. **Install Prerequisites**:
   - [Docker Desktop](https://www.docker.com/products/docker-desktop)
   - [Visual Studio Code](https://code.visualstudio.com/)
   - [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

2. **Open in Container**:
   - Open this project folder in VS Code
   - Press `F1` or `Cmd/Ctrl+Shift+P`
   - Select "Dev Containers: Reopen in Container"
   - Wait for the container to build (first time takes ~5 minutes)

3. **Verify Installation**:
   ```bash
   julia --version
   ```

### Running Tests

Once inside the container, you can run Julia tests:

```bash
julia test_hashed_prefix_dict.jl
```

### Using Julia REPL

Open a terminal in VS Code and type:
```bash
julia
```

Or use the VS Code Julia extension's integrated REPL.

## Customization

### Adding Julia Packages

Edit the Dockerfile to add more packages:
```dockerfile
RUN julia -e 'using Pkg; Pkg.add(["PackageName"])'
```

Then rebuild the container:
- Press `F1` → "Dev Containers: Rebuild Container"

### Modifying Settings

Edit `devcontainer.json` to customize VS Code settings or add extensions.

## Troubleshooting

**Container won't build?**
- Check Docker is running
- Try "Dev Containers: Rebuild Container Without Cache"

**Julia command not found?**
- Rebuild the container
- Check the postCreateCommand output for errors

**Slow performance?**
- Allocate more resources to Docker in Docker Desktop settings
- Recommended: 4+ GB RAM, 2+ CPUs
