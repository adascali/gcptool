#!/bin/bash
# List all snapshots in a project
# Usage: ./gcp-snapshots.sh <project-id>
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gcp-tools.sh"
list_snapshots "$@"

