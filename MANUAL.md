# GCPTOOL - GCP Compute Engine Automation Toolkit

## NAME

**gcptool** - Command-line toolkit for managing Google Cloud Platform Compute Engine instances across multiple projects

## SYNOPSIS

```
gcptool <command> [options] [arguments]
gcptool menu
gcptool help
```

## DESCRIPTION

**gcptool** is an optimized bash toolkit that simplifies day-to-day GCP Compute Engine operations. It provides caching for fast repeated queries, parallel execution for batch operations, and auto-detection of zones to reduce typing.

Designed for teams managing AEM (Adobe Experience Manager) infrastructure on GCP, it includes a dedicated command to open the Granite login page directly in your browser.

---

## COMMANDS

### Project Management

#### `gcptool projects`

List all GCP projects you have access to.

**Example:**
```bash
gcptool projects
```

**Output:**
```
PROJECT_ID      NAME                    LIFECYCLE_STATE
adbe-gcp0766    bpbu500 - Qiddiya       ACTIVE
adbe-gcp0737    bpbu499 - ams-stage     ACTIVE
```

---

### Instance Management

#### `gcptool instances <project> [--refresh]`

List all Compute Engine instances in a project with their status, IPs, and zones.

**Arguments:**
- `<project>` - GCP project ID (required)
- `--refresh` - Bypass cache and fetch fresh data

**Example:**
```bash
gcptool instances adbe-gcp0766
gcptool instances adbe-gcp0766 --refresh
```

**Output includes:**
- Instance name
- Zone
- Status (color-coded: green=RUNNING, red=TERMINATED)
- External IP
- Internal IP

**Note:** Results are cached for 5 minutes for faster subsequent queries.

---

#### `gcptool ip <project> <instance> [zone] [external|internal]`

Get the IP address of a specific instance.

**Arguments:**
- `<project>` - GCP project ID (required)
- `<instance>` - Instance name (required)
- `[zone]` - Zone (optional, auto-detected)
- `[external|internal]` - IP type (optional, default: external)

**Examples:**
```bash
# Get external IP
gcptool ip adbe-gcp0766 qiddiya-prod-author1mecentral2

# Get internal IP
gcptool ip adbe-gcp0766 qiddiya-prod-author1mecentral2 "" internal
```

---

#### `gcptool ssh <project> <instance> [zone]`

Open an SSH session to an instance.

**Arguments:**
- `<project>` - GCP project ID (required)
- `<instance>` - Instance name (required)
- `[zone]` - Zone (optional, auto-detected)

**Example:**
```bash
gcptool ssh adbe-gcp0766 qiddiya-dev-author1mecentral2
```

**Note:** Uses `gcloud compute ssh` under the hood. Requires proper SSH key configuration.

---

#### `gcptool start <project> <instance1> [instance2] ...`

Start one or more stopped instances. Multiple instances are started in parallel.

**Arguments:**
- `<project>` - GCP project ID (required)
- `<instance1> [instance2] ...` - One or more instance names

**Examples:**
```bash
# Start single instance
gcptool start adbe-gcp0766 qiddiya-dev-author1mecentral2

# Start multiple instances in parallel
gcptool start adbe-gcp0766 qiddiya-dev-author1mecentral2 qiddiya-dev-publish1mecentral2
```

**After starting:** The command waits briefly and displays the new IP addresses.

---

#### `gcptool stop <project> <instance1> [instance2] ... [--force]`

Stop one or more running instances. Multiple instances are stopped in parallel.

**Arguments:**
- `<project>` - GCP project ID (required)
- `<instance1> [instance2] ...` - One or more instance names
- `--force` or `-f` - Skip confirmation prompt

**Examples:**
```bash
# Stop with confirmation prompt
gcptool stop adbe-gcp0766 qiddiya-dev-author1mecentral2

# Stop multiple without confirmation
gcptool stop adbe-gcp0766 vm1 vm2 vm3 --force
```

**⚠️ Safety:** Without `--force`, you will be asked to confirm before stopping.

---

### Snapshot Management

#### `gcptool snapshot <project> <disk> [zone] [snapshot_name]`

Create a point-in-time snapshot of a persistent disk.

**Arguments:**
- `<project>` - GCP project ID (required)
- `<disk>` - Disk name (required)
- `[zone]` - Zone (optional, auto-detected)
- `[snapshot_name]` - Custom name (optional, auto-generated with timestamp)

**Examples:**
```bash
# Auto-generated name: disk-snap-20251217-143052
gcptool snapshot adbe-gcp0766 qiddiya-prod-author1mecentral2

# Custom snapshot name
gcptool snapshot adbe-gcp0766 qiddiya-prod-author1mecentral2 "" my-backup-before-upgrade
```

---

#### `gcptool snapshots <project>`

List all snapshots in a project, sorted by creation date (newest first).

**Arguments:**
- `<project>` - GCP project ID (required)

**Example:**
```bash
gcptool snapshots adbe-gcp0766
```

**Output includes:**
- Snapshot name
- Size in GB
- Status
- Creation date
- Source disk

---

### Quick Access Commands

#### `gcptool status`

Show a quick overview of all projects with running/stopped instance counts.

**Example:**
```bash
gcptool status
```

**Output:**
```
[adbe-gcp0766]
  Running: 32  Stopped: 2

[adbe-gcp0737]
  Running: 8   Stopped: 13
```

---

#### `gcptool search <pattern>`

Search for instances by name pattern across all projects.

**Arguments:**
- `<pattern>` - Search pattern (case-insensitive)

**Examples:**
```bash
gcptool search author      # Find all author instances
gcptool search prod        # Find all prod instances
gcptool search dispatcher  # Find all dispatcher instances
```

---

#### `gcptool aem <project> <instance> [port]`

Open the AEM Granite login page in your default browser.

**Arguments:**
- `<project>` - GCP project ID (required)
- `<instance>` - Instance name (required)
- `[port]` - Port number (optional, default: 443)

**Example:**
```bash
gcptool aem adbe-gcp0766 qiddiya-prod-author1mecentral2
```

**Opens:** `https://<external-ip>/libs/granite/core/content/login.html`

---

### Utility Commands

#### `gcptool cache-clear`

Clear all cached data. Use this if you need fresh data immediately.

**Example:**
```bash
gcptool cache-clear
```

---

#### `gcptool menu`

Launch the interactive menu for guided operation.

**Example:**
```bash
gcptool menu
# or simply:
gcptool
```

---

#### `gcptool help`

Display help message with all available commands.

**Example:**
```bash
gcptool help
```

---

## CACHING

To improve performance, **gcptool** caches API responses locally.

| Data Type | Cache Duration | Location |
|-----------|----------------|----------|
| Project list | 5 minutes | `~/.gcp-tools/cache/projects.cache` |
| Instance list | 5 minutes | `~/.gcp-tools/cache/instances_<project>.cache` |

### Bypassing Cache

```bash
# Refresh instance list
gcptool instances my-project --refresh

# Clear all cache
gcptool cache-clear
```

---

## CONFIGURATION

### Files

| Path | Description |
|------|-------------|
| `~/.gcp-tools/` | Configuration directory |
| `~/.gcp-tools/cache/` | Cache files |
| `/Users/adascali/gcp-automation/` | Script installation directory |

### Shell Configuration

Added to `~/.zshrc`:
```bash
export PATH="$HOME/bin:$PATH"
source /Users/adascali/gcp-automation/gcp-completion.bash
```

---

## TAB COMPLETION

Tab completion is available for commands, project names, and instance names.

**Requirements:**
- Run `gcptool instances <project>` once to cache instance names
- Completion data is read from cache files

**Examples:**
```bash
gcptool <TAB>                    # Complete commands
gcptool instances adbe<TAB>      # Complete project names
gcptool ssh adbe-gcp0766 qid<TAB> # Complete instance names
```

---

## EXAMPLES

### Daily Operations

```bash
# Morning check - see what's running
gcptool status

# List all instances in a project
gcptool instances adbe-gcp0766

# Find all author servers
gcptool search author

# SSH into dev author for debugging
gcptool ssh adbe-gcp0766 qiddiya-dev-author1mecentral2

# Open prod author AEM login
gcptool aem adbe-gcp0766 qiddiya-prod-author1mecentral2
```

### Starting/Stopping Environments

```bash
# Start dev environment (parallel)
gcptool start adbe-gcp0766 \
    qiddiya-dev-author1mecentral2 \
    qiddiya-dev-publish1mecentral2 \
    qiddiya-dev-dispatcher1mecentral2

# Stop dev environment at end of day
gcptool stop adbe-gcp0766 \
    qiddiya-dev-author1mecentral2 \
    qiddiya-dev-publish1mecentral2 \
    qiddiya-dev-dispatcher1mecentral2
```

### Backup Operations

```bash
# Create snapshot before upgrade
gcptool snapshot adbe-gcp0766 qiddiya-prod-author1mecentral2 "" pre-upgrade-backup

# List recent snapshots
gcptool snapshots adbe-gcp0766
```

---

## EXIT CODES

| Code | Description |
|------|-------------|
| 0 | Success |
| 1 | Error (invalid arguments, instance not found, API error) |

---

## PREREQUISITES

- **gcloud CLI** installed and in PATH
- **Authentication:** `gcloud auth login` completed
- **Permissions:** Compute Engine Admin or Viewer role (depending on operation)

---

## TROUBLESHOOTING

### "Could not find instance"

```bash
# Refresh the cache
gcptool instances my-project --refresh
```

### Authentication Expired

```bash
gcloud auth login
```

### Permission Denied

Ensure your GCP account has the necessary IAM roles:
- `roles/compute.viewer` - For read operations
- `roles/compute.instanceAdmin` - For start/stop operations
- `roles/compute.storageAdmin` - For snapshot operations

### Command Not Found

```bash
source ~/.zshrc
```

---

## SEE ALSO

- `gcloud compute instances list`
- `gcloud compute instances start`
- `gcloud compute instances stop`
- `gcloud compute disks snapshot`

---

## VERSION

GCP Tools v1.0 - Optimized Edition

---

## AUTHOR

Generated with AI assistance for Adobe Managed Services team.

---

## LICENSE

MIT License - Free to use and modify.

