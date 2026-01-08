#!/bin/bash
# Stop a GCP instance
# Usage: ./gcp-stop.sh <project-id> <instance-name> [zone]
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gcp-tools.sh"
stop_instance "$@"

