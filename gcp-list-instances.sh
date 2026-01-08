#!/bin/bash
# List all instances in a project
# Usage: ./gcp-list-instances.sh <project-id>
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gcp-tools.sh"
list_instances "$@"

