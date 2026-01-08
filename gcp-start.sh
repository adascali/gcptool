#!/bin/bash
# Start a GCP instance
# Usage: ./gcp-start.sh <project-id> <instance-name> [zone]
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gcp-tools.sh"
start_instance "$@"

