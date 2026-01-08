#!/bin/bash
#===============================================================================
# GCP Tools - GCP Compute Engine Helpers with Caching
# Version 2.0 - Added caching, snapshots, AEM support
#===============================================================================

set -o pipefail

# Configuration
CONFIG_DIR="$HOME/.gcp-tools"
CACHE_DIR="$CONFIG_DIR/cache"
CACHE_TTL=300  # 5 minutes

mkdir -p "$CACHE_DIR" 2>/dev/null

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

print_header() {
    echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_error() { echo -e "${RED}✗ $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_info() { echo -e "${YELLOW}→ $1${NC}"; }

confirm_action() {
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

#-------------------------------------------------------------------------------
# Caching System
#-------------------------------------------------------------------------------

_cache_file() { echo "$CACHE_DIR/${1//\//_}.cache"; }

_cache_valid() {
    local cache_file="$(_cache_file "$1")"
    if [[ -f "$cache_file" ]]; then
        local cache_age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)))
        [[ $cache_age -lt $CACHE_TTL ]]
    else
        return 1
    fi
}

_cache_read() { cat "$(_cache_file "$1")" 2>/dev/null; }
_cache_write() { cat > "$(_cache_file "$1")"; }

cache_clear() {
    rm -f "$CACHE_DIR"/*.cache 2>/dev/null
    print_success "Cache cleared"
}

#-------------------------------------------------------------------------------
# Optimized Data Fetching
#-------------------------------------------------------------------------------

_get_projects() {
    local cache_key="projects"
    if _cache_valid "$cache_key"; then
        _cache_read "$cache_key"
    else
        gcloud projects list --format="value(projectId)" 2>/dev/null | tee >(_cache_write "$cache_key")
    fi
}

_get_instances_raw() {
    local project="$1"
    local cache_key="instances_${project}"
    
    if _cache_valid "$cache_key"; then
        _cache_read "$cache_key"
    else
        gcloud compute instances list \
            --project="$project" \
            --format="csv[no-heading](name,zone.basename(),status,networkInterfaces[0].accessConfigs[0].natIP,networkInterfaces[0].networkIP)" \
            2>/dev/null | tee >(_cache_write "$cache_key")
    fi
}

_get_zone() {
    local project="$1"
    local instance="$2"
    _get_instances_raw "$project" | grep "^${instance}," | cut -d',' -f2 | head -1
}

_get_ip_fast() {
    local project="$1"
    local instance="$2"
    local ip_type="${3:-external}"
    
    local data=$(_get_instances_raw "$project" | grep "^${instance},")
    
    if [[ "$ip_type" == "internal" ]]; then
        echo "$data" | cut -d',' -f5
    else
        echo "$data" | cut -d',' -f4
    fi
}

#-------------------------------------------------------------------------------
# Commands
#-------------------------------------------------------------------------------

list_projects() {
    print_header "GCP Projects"
    gcloud projects list --format="table(projectId,name,lifecycleState)" --sort-by=projectId
}

list_instances() {
    local project="$1"
    local refresh="$2"
    
    if [[ -z "$project" ]]; then
        print_error "Usage: list_instances <project> [--refresh]"
        return 1
    fi
    
    [[ "$refresh" == "--refresh" ]] && rm -f "$(_cache_file "instances_${project}")"
    
    print_header "Instances in $project"
    
    local data=$(_get_instances_raw "$project")
    
    printf "${BOLD}%-40s %-15s %-12s %-16s %-15s${NC}\n" "NAME" "ZONE" "STATUS" "EXTERNAL_IP" "INTERNAL_IP"
    echo "────────────────────────────────────────────────────────────────────────────────────────"
    
    echo "$data" | while IFS=',' read -r name zone status ext_ip int_ip; do
        local status_color="$GREEN"
        [[ "$status" == "TERMINATED" ]] && status_color="$RED"
        printf "%-40s %-15s ${status_color}%-12s${NC} %-16s %-15s\n" \
            "$name" "$zone" "$status" "${ext_ip:--}" "$int_ip"
    done
    
    echo -e "\n${YELLOW}Cached for ${CACHE_TTL}s. Use --refresh to update.${NC}"
}

ssh_to_instance() {
    local project="$1"
    local instance="$2"
    local zone="${3:-$(_get_zone "$project" "$instance")}"
    
    if [[ -z "$project" || -z "$instance" ]]; then
        print_error "Usage: ssh <project> <instance> [zone]"
        return 1
    fi
    
    if [[ -z "$zone" ]]; then
        print_error "Could not find zone for $instance"
        return 1
    fi
    
    print_info "Connecting to $instance in $project ($zone)..."
    gcloud compute ssh "$instance" --project="$project" --zone="$zone" --tunnel-through-iap
}

start_instance() {
    local project="$1"
    shift
    local instances=("$@")
    
    if [[ -z "$project" || ${#instances[@]} -eq 0 ]]; then
        print_error "Usage: start <project> <instance1> [instance2] ..."
        return 1
    fi
    
    print_header "Starting ${#instances[@]} Instance(s)"
    
    # Parallel start
    local pids=()
    for instance in "${instances[@]}"; do
        local zone=$(_get_zone "$project" "$instance")
        print_info "Starting $instance..."
        gcloud compute instances start "$instance" --project="$project" --zone="$zone" --async &
        pids+=($!)
    done
    
    for pid in "${pids[@]}"; do wait "$pid"; done
    
    rm -f "$(_cache_file "instances_${project}")"
    print_success "Start command sent"
}

stop_instance() {
    local project="$1"
    shift
    local instances=("$@")
    
    if [[ -z "$project" || ${#instances[@]} -eq 0 ]]; then
        print_error "Usage: stop <project> <instance1> [instance2] ..."
        return 1
    fi
    
    print_header "Stopping ${#instances[@]} Instance(s)"
    
    echo -e "${RED}${BOLD}⚠️  WARNING: This will STOP the instance(s)!${NC}"
    if ! confirm_action; then
        print_info "Cancelled"
        return 0
    fi
    
    local pids=()
    for instance in "${instances[@]}"; do
        local zone=$(_get_zone "$project" "$instance")
        print_info "Stopping $instance..."
        gcloud compute instances stop "$instance" --project="$project" --zone="$zone" --async &
        pids+=($!)
    done
    
    for pid in "${pids[@]}"; do wait "$pid"; done
    
    rm -f "$(_cache_file "instances_${project}")"
    print_success "Stop command sent"
}

get_instance_ip() {
    local project="$1"
    local instance="$2"
    local ip_type="${3:-external}"
    
    if [[ -z "$project" || -z "$instance" ]]; then
        print_error "Usage: ip <project> <instance> [external|internal]"
        return 1
    fi
    
    local ip=$(_get_ip_fast "$project" "$instance" "$ip_type")
    
    if [[ -n "$ip" && "$ip" != "-" ]]; then
        echo "$ip"
    else
        print_error "Could not get IP for $instance"
        return 1
    fi
}

create_snapshot() {
    local project="$1"
    local disk="$2"
    local zone="$3"
    local snapshot_name="${4:-${disk}-snap-$(date +%Y%m%d-%H%M%S)}"
    
    if [[ -z "$project" || -z "$disk" ]]; then
        print_error "Usage: snapshot <project> <disk> [zone] [snapshot_name]"
        return 1
    fi
    
    if [[ -z "$zone" ]]; then
        zone=$(gcloud compute disks list --project="$project" --filter="name=$disk" --format="value(zone.basename())" | head -1)
    fi
    
    print_header "Creating Snapshot"
    print_info "Disk: $disk | Zone: $zone"
    print_info "Snapshot: $snapshot_name"
    
    if gcloud compute disks snapshot "$disk" --project="$project" --zone="$zone" --snapshot-names="$snapshot_name"; then
        print_success "Snapshot created: $snapshot_name"
    else
        print_error "Failed to create snapshot"
        return 1
    fi
}

list_snapshots() {
    local project="$1"
    
    if [[ -z "$project" ]]; then
        print_error "Usage: snapshots <project>"
        return 1
    fi
    
    print_header "Snapshots in $project"
    gcloud compute snapshots list \
        --project="$project" \
        --format="table(name,diskSizeGb,status,creationTimestamp.date(),sourceDisk.basename())" \
        --sort-by=~creationTimestamp
}

open_aem_login() {
    local project="$1"
    local instance="$2"
    
    if [[ -z "$project" || -z "$instance" ]]; then
        print_error "Usage: aem <project> <instance>"
        return 1
    fi
    
    local ip=$(_get_ip_fast "$project" "$instance" "external")
    
    if [[ -z "$ip" || "$ip" == "-" ]]; then
        print_error "Could not get IP for $instance"
        return 1
    fi
    
    local url="https://${ip}/libs/granite/core/content/login.html"
    print_info "Opening: $url"
    
    case "$(uname -s)" in
        Darwin) open "$url" ;;
        Linux) xdg-open "$url" 2>/dev/null ;;
        *) echo "Open manually: $url" ;;
    esac
}

show_help() {
    cat << 'EOF'
GCP Tools v2.0 - With Caching

Usage: gcp-tools.sh <command> [args]

Commands:
    projects                       List all GCP projects
    instances <project> [--refresh] List instances (cached)
    ssh <project> <instance>       SSH to an instance
    start <project> <vm1> [vm2...] Start instance(s) in parallel
    stop <project> <vm1> [vm2...]  Stop instance(s)
    ip <project> <instance>        Get instance IP
    snapshot <project> <disk>      Create disk snapshot
    snapshots <project>            List all snapshots
    aem <project> <instance>       Open AEM login page
    cache-clear                    Clear cache
    help                           Show this help

Examples:
    ./gcp-tools.sh instances my-project --refresh
    ./gcp-tools.sh start my-project vm1 vm2 vm3
    ./gcp-tools.sh aem my-project my-aem-server
EOF
}

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
        snapshot) create_snapshot "$@" ;;
        snapshots) list_snapshots "$@" ;;
        aem) open_aem_login "$@" ;;
        cache-clear) cache_clear ;;
        help|--help|-h) show_help ;;
        *) show_help ;;
    esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"

