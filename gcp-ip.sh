#!/bin/bash
# Get IP address of a GCP instance
# Usage: ./gcp-ip.sh <project-id> <instance-name> [zone] [external|internal]
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gcp-tools.sh"
get_instance_ip "$@"

