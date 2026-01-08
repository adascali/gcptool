# gcptool - GCP Compute Engine Automation Toolkit

A bash CLI toolkit to manage Google Cloud Platform Compute Engine instances across multiple projects. Built for teams managing AEM (Adobe Experience Manager) infrastructure.

## Prerequisites

- `gcloud` CLI installed and configured
- Authenticated with: `gcloud auth login`
- Proper IAM permissions for Compute Engine operations

## Installation

```bash
# Clone the repository
git clone https://github.com/adascali/gcptool.git
cd gcptool

# Make executable
chmod +x gcp-tools.sh

# Add to your PATH (choose one):

# Option 1: Symlink (recommended)
ln -s "$(pwd)/gcp-tools.sh" /usr/local/bin/gcptool

# Option 2: Add to .zshrc/.bashrc
echo 'alias gcptool="/path/to/gcptool/gcp-tools.sh"' >> ~/.zshrc

# Enable tab completion
echo 'source /path/to/gcptool/gcp-completion.bash' >> ~/.zshrc
```

## Quick Start

```bash
# List all projects
gcptool projects

# List instances (auto-detects project!)
gcptool ssh qiddiya-dev-author1

# Get help
gcptool help
```

## Available Commands

| Command | Description | Example |
|---------|-------------|---------|
| `projects` | List all GCP projects | `gcptool projects` |
| `instances` | List all VMs | `gcptool list instances` |
| `ssh` | SSH to an instance | `gcptool ssh my-instance` |
| `start` | Start instance(s) | `gcptool start my-project vm1 vm2` |
| `stop` | Stop instance(s) | `gcptool stop my-project vm1` |
| `ip` | Get instance IP | `gcptool ip my-instance` |
| `snapshot` | Create disk snapshot | `gcptool snapshot my-project my-disk` |
| `aem` | Open AEM login in browser | `gcptool aem my-instance` |
| `crx` | Open CRX/DE | `gcptool crx my-instance` |
| `status` | Quick status all projects | `gcptool status` |
| `search` | Search instances by name | `gcptool search author` |

## Key Features

### Auto-Detection
Most commands auto-detect the project from the instance name:
```bash
# No need to specify project!
gcptool ssh qiddiya-dev-author1mecentral2
gcptool ip qiddiya-prod-publish1mecentral2
gcptool aem qiddiya-dev-author1mecentral2
```

### AMSTOOL-Style SSH Commands
```bash
gcptool ssha <project>    # SSH to all Authors
gcptool sshp <project>    # SSH to all Publishers
gcptool sshd <project>    # SSH to all Dispatchers
gcptool sshaem <project>  # SSH to all AEM hosts
```

### Parallel Operations
```bash
# Start multiple VMs in parallel
gcptool start my-project vm1 vm2 vm3

# Stop with force flag (no confirmation)
gcptool stop my-project vm1 vm2 --force
```

### Remote Commands
```bash
# Run command on single instance
gcptool cmd my-instance 'uptime'

# Run on all matching instances
gcptool cmdx my-project publish 'df -h'
```

### Load Balancer Management
```bash
gcptool lb status my-dispatcher    # Check LB membership
gcptool lb disable my-dispatcher   # Remove from LB
gcptool lb enable my-dispatcher    # Add to LB
```

## Caching

Results are cached for 5 minutes for faster subsequent queries.

```bash
gcptool cache          # Update cache
gcptool cache-clear    # Clear cache
gcptool list instances --refresh  # Bypass cache
```

## Documentation

- **Quick Reference**: `gcptool cheat`
- **Full Manual**: `gcptool man`
- **Help**: `gcptool help`

## Troubleshooting

### Not Authenticated
```bash
gcloud auth login
```

### Instance Not Found
```bash
gcptool cache          # Refresh cache
gcptool search <name>  # Search for instance
```

### Permission Denied
Ensure your GCP account has the necessary IAM roles:
- `roles/compute.viewer` - For read operations
- `roles/compute.instanceAdmin` - For start/stop
- `roles/compute.storageAdmin` - For snapshots

## License

MIT - Feel free to modify and distribute.

## Author

Created by Diana Adascalitei, Dec 2025
