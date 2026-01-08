#!/bin/bash
# List all GCP projects
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gcp-tools.sh"
list_projects

