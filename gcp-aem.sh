#!/bin/bash
# Open AEM login page for a GCP instance
# Usage: ./gcp-aem.sh <project-id> <instance-name> [zone]
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gcp-tools.sh"
open_aem_login "$@"

