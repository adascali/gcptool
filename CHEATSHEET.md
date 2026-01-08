# gcptool Quick Reference
**Created by Diana Adascalitei, Dec 2025**

Most commands auto-detect the project! Just use the instance name.

## 📋 LIST Commands

| Command | Description |
|---------|-------------|
| `gcptool list projects` | List all GCP projects |
| `gcptool list instances [project]` | List all VMs |
| `gcptool list snapshots <project>` | List all snapshots |
| `gcptool list disks <project>` | List all disks |

## 🔌 SSH Commands

| Command | Description |
|---------|-------------|
| `gcptool ssh <instance>` | SSH to instance *(auto-finds project)* |
| `gcptool ssha <project>` | SSH to all **Authors** |
| `gcptool sshp <project>` | SSH to all **Publishers** |
| `gcptool sshd <project>` | SSH to all **Dispatchers** |
| `gcptool sshpd <project>` | SSH to all **Publishers & Dispatchers** |
| `gcptool sshaem <project>` | SSH to all **AEM** (Authors + Publishers) |
| `gcptool sshx <project> [filter]` | SSH to all matching hosts |

## 💻 Remote Commands

| Command | Description |
|---------|-------------|
| `gcptool cmd <instance> '<command>'` | Run command on instance |
| `gcptool cmdx <project> <filter> '<cmd>'` | Run command on matching instances |
| `gcptool scp upload <proj> <inst> <local> [remote]` | Upload file |
| `gcptool scp download <proj> <inst> <remote> [local]` | Download file |

## 🌐 Browser/URL Commands

| Command | Description |
|---------|-------------|
| `gcptool url <instance> [path]` | Open URL in browser |
| `gcptool aem <instance>` | Open AEM Granite login |
| `gcptool crx <instance>` | Open CRX/DE |
| `gcptool console <instance>` | Open Felix Console |

## ▶️ Instance Management

| Command | Description |
|---------|-------------|
| `gcptool start <project> <vm1> [vm2...]` | Start instance(s) |
| `gcptool stop <project> <vm1> [vm2...] [-f]` | Stop instance(s) |
| `gcptool snapshot <project> <disk>` | Create disk snapshot |
| `gcptool info <instance>` | Show instance details |
| `gcptool ip <instance>` | Get instance IP |

## 🔧 Utilities

| Command | Description |
|---------|-------------|
| `gcptool status` | Quick status all projects |
| `gcptool search <pattern>` | Search instances by name |
| `gcptool cache` | Update cache |
| `gcptool cache-clear` | Clear cache |

---

## 🚀 Common Workflows (Simplified!)

### Morning Check
```bash
gcptool status
```

### SSH to Instance (no project needed!)
```bash
gcptool ssh qiddiya-dev-author1mecentral2
```

### Get IP
```bash
gcptool ip qiddiya-dev-author1mecentral2
```

### Open AEM Login
```bash
gcptool aem qiddiya-prod-author1mecentral2
```

### Open CRX/DE
```bash
gcptool crx qiddiya-dev-author1mecentral2
```

### Run Command
```bash
gcptool cmd qiddiya-dev-author1mecentral2 'uptime'
```

### SSH to All Authors
```bash
gcptool ssha adbe-gcp0766
```

### Run Command on All Publishers
```bash
gcptool cmdx adbe-gcp0766 publish 'uptime'
```

---

## 📁 Your Projects

| Project ID | Name |
|------------|------|
| `adbe-gcp0766` | Qiddiya |
| `adbe-gcp0737` | ams-stage |

---

*Cache: 5 min TTL • Auto-detects project from instance name*
