# GCP Compute Engine Automation Toolkit

A collection of bash scripts to automate common Google Cloud Platform Compute Engine operations across multiple projects.

## Prerequisites

- `gcloud` CLI installed and configured
- Authenticated with: `gcloud auth login`
- Proper IAM permissions for Compute Engine operations

## Quick Start

```bash
# Make the script executable
chmod +x gcp-tools.sh

# Run the interactive menu
./gcp-tools.sh

# Or use direct commands
./gcp-tools.sh help
```

## Available Commands

| Command | Description | Example |
|---------|-------------|---------|
| `projects` | List all GCP projects | `./gcp-tools.sh projects` |
| `instances` | List all VMs in a project | `./gcp-tools.sh instances my-project` |
| `ip` | Get instance IP address | `./gcp-tools.sh ip my-project my-vm` |
| `ssh` | SSH to an instance | `./gcp-tools.sh ssh my-project my-vm` |
| `start` | Start an instance | `./gcp-tools.sh start my-project my-vm` |
| `stop` | Stop an instance | `./gcp-tools.sh stop my-project my-vm` |
| `snapshot` | Create disk snapshot | `./gcp-tools.sh snapshot my-project my-disk` |
| `snapshots` | List all snapshots | `./gcp-tools.sh snapshots my-project` |
| `aem` | Open AEM login in browser | `./gcp-tools.sh aem my-project my-aem-server` |
| `menu` | Interactive menu | `./gcp-tools.sh menu` |

## Usage Examples

### List All Projects
```bash
./gcp-tools.sh projects
```

### List Instances in a Project
```bash
./gcp-tools.sh instances my-gcp-project
```

### SSH to an Instance
```bash
# Zone is auto-detected
./gcp-tools.sh ssh my-project my-instance-name

# Or specify zone explicitly
./gcp-tools.sh ssh my-project my-instance-name us-central1-a
```

### Start/Stop Instances
```bash
# Start an instance
./gcp-tools.sh start my-project my-instance

# Stop an instance (will prompt for confirmation)
./gcp-tools.sh stop my-project my-instance
```

### Create a Snapshot
```bash
# Auto-generates snapshot name with timestamp
./gcp-tools.sh snapshot my-project my-disk-name

# Custom snapshot name
./gcp-tools.sh snapshot my-project my-disk us-central1-a my-backup-snapshot
```

### Open AEM Login Page
```bash
# Opens https://<instance-ip>/libs/granite/core/content/login.html
./gcp-tools.sh aem my-project my-aem-instance
```

## Interactive Mode

Run without arguments or with `menu` to get an interactive guided experience:

```bash
./gcp-tools.sh
# or
./gcp-tools.sh menu
```

## Individual Scripts

For convenience, you can also use the individual wrapper scripts:

- `gcp-list-projects.sh` - List all projects
- `gcp-list-instances.sh <project>` - List instances
- `gcp-ssh.sh <project> <instance>` - SSH to instance
- `gcp-start.sh <project> <instance>` - Start instance
- `gcp-stop.sh <project> <instance>` - Stop instance
- `gcp-snapshot.sh <project> <disk>` - Create snapshot
- `gcp-aem.sh <project> <instance>` - Open AEM login

## Tips

1. **Zone Auto-Detection**: Most commands auto-detect the zone if not provided
2. **Tab Completion**: Works with gcloud's built-in completion
3. **Multiple Projects**: Use `projects` command to see all available projects
4. **Scripting**: Source the main script to use functions in your own scripts:
   ```bash
   source gcp-tools.sh
   list_instances "my-project"
   ```

## Troubleshooting

### Permission Denied
```bash
chmod +x gcp-tools.sh
```

### Not Authenticated
```bash
gcloud auth login
gcloud config set project YOUR_DEFAULT_PROJECT
```

### Instance Not Found
- Verify the instance name with `./gcp-tools.sh instances <project>`
- Check that you have access to the project

## License

MIT - Feel free to modify and distribute.

