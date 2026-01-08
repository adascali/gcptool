#!/bin/bash
# Create a snapshot of a GCP disk
# Usage: ./gcp-snapshot.sh <project-id> <disk-name> [zone] [snapshot-name]
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gcp-tools.sh"
create_snapshot "$@"

