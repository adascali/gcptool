#!/bin/bash
#===============================================================================
# GCP Tools - Simple GCP Compute Engine Helpers
# Version 1.0 - Basic commands
#===============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_error() { echo -e "${RED}Error: $1${NC}"; }
print_success() { echo -e "${GREEN}$1${NC}"; }
print_info() { echo -e "${YELLOW}$1${NC}"; }

# List all projects
list_projects() {
    echo "Fetching GCP projects..."
    gcloud projects list --format="table(projectId,name,lifecycleState)"
}

# List instances in a project
list_instances() {
    local project="$1"
    if [[ -z "$project" ]]; then
        print_error "Usage: list_instances <project>"
        return 1
    fi
    
    echo "Fetching instances in $project..."
    gcloud compute instances list \
        --project="$project" \
        --format="table(name,zone.basename(),status,networkInterfaces[0].accessConfigs[0].natIP)"
}

# Get zone for an instance
get_zone() {
    local project="$1"
    local instance="$2"
    
    gcloud compute instances list \
        --project="$project" \
        --filter="name=$instance" \
        --format="value(zone.basename())" 2>/dev/null | head -1
}

# SSH to instance
ssh_to_instance() {
    local project="$1"
    local instance="$2"
    local zone="${3:-$(get_zone "$project" "$instance")}"
    
    if [[ -z "$project" || -z "$instance" ]]; then
        print_error "Usage: ssh_to_instance <project> <instance> [zone]"
        return 1
    fi
    
    if [[ -z "$zone" ]]; then
        print_error "Could not find zone for $instance"
        return 1
    fi
    
    print_info "Connecting to $instance..."
    gcloud compute ssh "$instance" --project="$project" --zone="$zone"
}

# Start instance
start_instance() {
    local project="$1"
    local instance="$2"
    local zone="${3:-$(get_zone "$project" "$instance")}"
    
    if [[ -z "$project" || -z "$instance" ]]; then
        print_error "Usage: start_instance <project> <instance> [zone]"
        return 1
    fi
    
    print_info "Starting $instance..."
    gcloud compute instances start "$instance" --project="$project" --zone="$zone"
    print_success "Instance started"
}

# Stop instance
stop_instance() {
    local project="$1"
    local instance="$2"
    local zone="${3:-$(get_zone "$project" "$instance")}"
    
    if [[ -z "$project" || -z "$instance" ]]; then
        print_error "Usage: stop_instance <project> <instance> [zone]"
        return 1
    fi
    
    read -p "Are you sure you want to stop $instance? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Cancelled"
        return 0
    fi
    
    print_info "Stopping $instance..."
    gcloud compute instances stop "$instance" --project="$project" --zone="$zone"
    print_success "Instance stopped"
}

# Get instance IP
get_instance_ip() {
    local project="$1"
    local instance="$2"
    local zone="${3:-$(get_zone "$project" "$instance")}"
    
    gcloud compute instances describe "$instance" \
        --project="$project" \
        --zone="$zone" \
        --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null
}

# Show help
show_help() {
    cat << 'EOF'
GCP Tools v1.0 - Basic Commands

Usage: gcp-tools.sh <command> [args]

Commands:
    projects                    List all GCP projects
    instances <project>         List instances in a project
    ssh <project> <instance>    SSH to an instance
    start <project> <instance>  Start an instance
    stop <project> <instance>   Stop an instance
    ip <project> <instance>     Get instance IP
    help                        Show this help

Examples:
    ./gcp-tools.sh projects
    ./gcp-tools.sh instances my-project
    ./gcp-tools.sh ssh my-project my-vm
EOF
}

# Main
main() {
    local command="$1"
    shift 2>/dev/null || true
    
    case "$command" in
        projects) list_projects ;;
        instances) list_instances "$@" ;;
        ssh) ssh_to_instance "$@" ;;
        start) start_instance "$@" ;;
        stop) stop_instance "$@" ;;
        ip) get_instance_ip "$@" ;;
        help|--help|-h) show_help ;;
        *) show_help ;;
    esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"

