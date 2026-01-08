#!/bin/bash
# SSH to a GCP instance
# Usage: ./gcp-ssh.sh <project-id> <instance-name> [zone]
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gcp-tools.sh"
ssh_to_instance "$@"

