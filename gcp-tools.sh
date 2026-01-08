#!/bin/bash
#===============================================================================
# GCPTOOL - GCP Compute Engine Automation Toolkit
# Created by Diana Adascalitei, Dec 2025
# Description: Scripts to manage GCP Compute Engine instances across projects
#===============================================================================

set -o pipefail

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
CONFIG_DIR="$HOME/.gcp-tools"
CACHE_DIR="$CONFIG_DIR/cache"
CONFIG_FILE="$CONFIG_DIR/config"
CACHE_TTL=300  # Cache TTL in seconds (5 minutes)

# Resolve the actual script directory (handles symlinks)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"

# Create config directory if it doesn't exist
mkdir -p "$CACHE_DIR" 2>/dev/null

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'
DIM='\033[2m'

#-------------------------------------------------------------------------------
# Helper Functions
#-------------------------------------------------------------------------------

print_header() {
    echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${YELLOW}→ $1${NC}"; }
print_dim() { echo -e "${DIM}$1${NC}"; }

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
    if [[ -n "$1" ]]; then
        rm -f "$(_cache_file "$1")" 2>/dev/null
    else
        rm -f "$CACHE_DIR"/*.cache 2>/dev/null
        print_success "Cache cleared"
    fi
}

cache_update() {
    print_header "Updating GCPTOOL Cache"
    
    # Update projects cache
    print_info "Fetching projects..."
    gcloud projects list --format="value(projectId)" 2>/dev/null | _cache_write "projects"
    
    # Update instances for each project
    local projects=$(_cache_read "projects")
    for project in $projects; do
        print_info "Fetching instances for $project..."
        gcloud compute instances list \
            --project="$project" \
            --format="csv[no-heading](name,zone.basename(),status,networkInterfaces[0].accessConfigs[0].natIP,networkInterfaces[0].networkIP,machineType.basename())" \
            2>/dev/null | _cache_write "instances_${project}"
    done
    
    print_success "Cache updated"
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
            --format="csv[no-heading](name,zone.basename(),status,networkInterfaces[0].accessConfigs[0].natIP,networkInterfaces[0].networkIP,machineType.basename())" \
            2>/dev/null | tee >(_cache_write "$cache_key")
    fi
}

_get_zone() {
    local project="$1"
    local instance="$2"
    local zone=$(_get_instances_raw "$project" | grep "^${instance}," | cut -d',' -f2 | head -1)
    
    if [[ -n "$zone" ]]; then
        echo "$zone"
    else
        gcloud compute instances list \
            --project="$project" \
            --filter="name=$instance" \
            --format="value(zone.basename())" 2>/dev/null | head -1
    fi
}

_get_ip_fast() {
    local project="$1"
    local instance="$2"
    local ip_type="${3:-external}"
    
    local data=$(_get_instances_raw "$project" | grep "^${instance},")
    
    if [[ -n "$data" ]]; then
        if [[ "$ip_type" == "internal" ]]; then
            echo "$data" | cut -d',' -f5
        else
            echo "$data" | cut -d',' -f4
        fi
    fi
}

# Get instances by type (author, publish, dispatcher)
_get_instances_by_type() {
    local project="$1"
    local type="$2"
    _get_instances_raw "$project" | grep -i "$type" | cut -d',' -f1
}

# Find instance across all projects - returns "project:instance:zone"
_find_instance() {
    local instance="$1"
    local interactive="${2:-true}"
    local projects=$(_get_projects)
    
    # First try exact match
    for project in $projects; do
        local match=$(_get_instances_raw "$project" | grep "^${instance},")
        if [[ -n "$match" ]]; then
            local zone=$(echo "$match" | cut -d',' -f2)
            echo "${project}:${instance}:${zone}"
            return 0
        fi
    done
    
    # Try partial match
    local all_matches=""
    for project in $projects; do
        local matches=$(_get_instances_raw "$project" | grep -i "$instance")
        if [[ -n "$matches" ]]; then
            while IFS=',' read -r name zone status ext_ip int_ip _; do
                all_matches+="${project}:${name}:${zone}:${status}:${ext_ip}"$'\n'
            done <<< "$matches"
        fi
    done
    
    # Remove trailing newline
    all_matches=$(echo "$all_matches" | sed '/^$/d')
    
    if [[ -z "$all_matches" ]]; then
        return 1
    fi
    
    local count=$(echo "$all_matches" | wc -l | tr -d ' ')
    
    if [[ "$count" -eq 1 ]]; then
        # Single match - use it
        local line=$(echo "$all_matches" | head -1)
        local project=$(echo "$line" | cut -d':' -f1)
        local name=$(echo "$line" | cut -d':' -f2)
        local zone=$(echo "$line" | cut -d':' -f3)
        echo "${project}:${name}:${zone}"
        return 0
    fi
    
    if [[ "$interactive" == "true" ]]; then
        # Multiple matches - show selection
        echo -e "\n${CYAN}Multiple instances match '${instance}':${NC}" >&2
        local i=1
        local selections=()
        while IFS=':' read -r project name zone status ext_ip; do
            local status_color="${GREEN}"
            [[ "$status" == "TERMINATED" ]] && status_color="${RED}"
            printf "  %2d) %-45s ${status_color}%-10s${NC} %s\n" "$i" "$name" "$status" "${ext_ip:--}" >&2
            selections+=("${project}:${name}:${zone}")
            ((i++))
        done <<< "$all_matches"
        
        echo "" >&2
        read -p "Select [1-$count]: " choice
        
        if [[ "$choice" -ge 1 && "$choice" -le "$count" ]] 2>/dev/null; then
            echo "${selections[$((choice-1))]}"
            return 0
        else
            echo -e "${RED}Invalid selection${NC}" >&2
            return 1
        fi
    else
        # Non-interactive - return first match
        local line=$(echo "$all_matches" | head -1)
        local project=$(echo "$line" | cut -d':' -f1)
        local name=$(echo "$line" | cut -d':' -f2)
        local zone=$(echo "$line" | cut -d':' -f3)
        echo "${project}:${name}:${zone}"
        return 0
    fi
}

# Resolve instance - handles both "project instance" and just "instance"
_resolve_instance() {
    local arg1="$1"
    local arg2="$2"
    
    # If both args provided, assume project + instance
    if [[ -n "$arg2" ]]; then
        local zone=$(_get_zone "$arg1" "$arg2")
        echo "${arg1}:${arg2}:${zone}"
        return 0
    fi
    
    # Only one arg - search for instance across all projects
    _find_instance "$arg1"
}

#-------------------------------------------------------------------------------
# LIST - List Information (like AMSTOOL list)
#-------------------------------------------------------------------------------

cmd_list() {
    local subcommand="${1:-projects}"
    shift 2>/dev/null || true
    
    case "$subcommand" in
        projects|proj)
            print_header "GCP Projects"
            gcloud projects list \
                --format="table(projectId,name,lifecycleState)" \
                --sort-by=projectId 2>/dev/null
            ;;
        instances|inst|vms)
            local filter="$1"
            local refresh="$2"
            
            print_header "Instances${filter:+ matching '$filter'}"
            
            local projects=$(_get_projects)
            
            for project in $projects; do
                [[ "$refresh" == "--refresh" ]] && cache_clear "instances_${project}"
                
                local data=$(_get_instances_raw "$project")
                
                # Filter if pattern provided
                if [[ -n "$filter" && "$filter" != "--refresh" ]]; then
                    data=$(echo "$data" | grep -i "$filter")
                fi
                
                if [[ -n "$data" ]]; then
                    echo -e "\n${BOLD}${CYAN}[$project]${NC}"
                    printf "${BOLD}%-45s %-15s %-12s %-16s %-15s${NC}\n" "NAME" "ZONE" "STATUS" "EXTERNAL_IP" "INTERNAL_IP"
                    echo "────────────────────────────────────────────────────────────────────────────────────────────────"
                    
                    echo "$data" | while IFS=',' read -r name zone status ext_ip int_ip machine_type; do
                        local status_color="$GREEN"
                        [[ "$status" == "TERMINATED" ]] && status_color="$RED"
                        [[ "$status" == "STOPPING" || "$status" == "STAGING" ]] && status_color="$YELLOW"
                        
                        printf "%-45s %-15s ${status_color}%-12s${NC} %-16s %-15s\n" \
                            "$name" "$zone" "$status" "${ext_ip:--}" "$int_ip"
                    done
                fi
            done
            
            print_dim "\nCached for ${CACHE_TTL}s. Use --refresh to update."
            ;;
        snapshots|snap)
            local filter="$1"
            
            if [[ -z "$filter" ]]; then
                echo -e "${YELLOW}Usage: gcptool list snapshots <instance-name-or-prefix>${NC}"
                echo -e "${DIM}Example: gcptool list snapshots qiddiya-prod-author${NC}"
                return 1
            fi
            
            print_header "Snapshots for '$filter'"
            
            local projects=$(_get_projects)
            for project in $projects; do
                local snapshots=$(gcloud compute snapshots list \
                    --project="$project" \
                    --format="csv[no-heading](name,diskSizeGb,status,creationTimestamp.date(),sourceDisk.basename())" \
                    2>/dev/null | grep -i "$filter")
                
                if [[ -n "$snapshots" ]]; then
                    echo -e "\n${BOLD}${CYAN}[$project]${NC}"
                    printf "${BOLD}%-50s %8s %-10s %-12s %-40s${NC}\n" "SNAPSHOT" "SIZE_GB" "STATUS" "CREATED" "SOURCE_DISK"
                    echo "──────────────────────────────────────────────────────────────────────────────────────────────────────────────"
                    
                    echo "$snapshots" | while IFS=',' read -r name size status created source; do
                        printf "%-50s %8s %-10s %-12s %-40s\n" "$name" "$size" "$status" "$created" "$source"
                    done
                fi
            done
            ;;
        disks)
            local filter="$1"
            
            if [[ -z "$filter" ]]; then
                echo -e "${YELLOW}Usage: gcptool list disks <instance-name-or-prefix>${NC}"
                echo -e "${DIM}Example: gcptool list disks qiddiya-prod-author${NC}"
                return 1
            fi
            
            print_header "Disks for '$filter'"
            
            local projects=$(_get_projects)
            for project in $projects; do
                local disks=$(gcloud compute disks list \
                    --project="$project" \
                    --format="csv[no-heading](name,zone.basename(),sizeGb,type.basename(),status,users.basename())" \
                    2>/dev/null | grep -i "$filter")
                
                if [[ -n "$disks" ]]; then
                    echo -e "\n${BOLD}${CYAN}[$project]${NC}"
                    printf "${BOLD}%-50s %-15s %8s %-15s %-10s %-30s${NC}\n" "DISK" "ZONE" "SIZE_GB" "TYPE" "STATUS" "ATTACHED_TO"
                    echo "──────────────────────────────────────────────────────────────────────────────────────────────────────────────"
                    
                    echo "$disks" | while IFS=',' read -r name zone size type status attached; do
                        printf "%-50s %-15s %8s %-15s %-10s %-30s\n" "$name" "$zone" "$size" "$type" "$status" "${attached:--}"
                    done
                fi
            done
            ;;
        *)
            echo "Usage: gcptool list <projects|instances|snapshots|disks> [project]"
            ;;
    esac
}

#-------------------------------------------------------------------------------
# SSH - SSH to Instance (like AMSTOOL ssh)
# Usage: gcptool ssh <instance>  OR  gcptool ssh <project> <instance>
#-------------------------------------------------------------------------------

cmd_ssh() {
    local arg1="$1"
    local arg2="$2"
    local arg3="$3"
    
    if [[ -z "$arg1" ]]; then
        echo -e "${YELLOW}Usage: gcptool ssh <instance>${NC}"
        echo -e "${YELLOW}   or: gcptool ssh <project> <instance>${NC}"
        return 1
    fi
    
    local result
    local project instance zone
    
    # Resolve the instance (handles both formats)
    result=$(_resolve_instance "$arg1" "$arg2")
    
    if [[ -z "$result" ]]; then
        print_error "Could not find instance '$arg1'"
        print_info "Try: gcptool search $arg1"
        return 1
    fi
    
    IFS=':' read -r project instance zone <<< "$result"
    
    # If zone was provided as arg3, use it
    [[ -n "$arg3" ]] && zone="$arg3"
    
    print_info "Connecting to $instance in $project ($zone)..."
    gcloud compute ssh "$instance" --project="$project" --zone="$zone" --tunnel-through-iap
}

# SSHA - SSH to all Authors (like AMSTOOL ssha)
cmd_ssha() {
    local project="$1"
    [[ -z "$project" ]] && { echo "Usage: gcptool ssha <project>"; return 1; }
    
    print_header "SSH to All Authors in $project"
    local authors=$(_get_instances_by_type "$project" "author")
    _ssh_multiple "$project" $authors
}

# SSHP - SSH to all Publishers (like AMSTOOL sshp)
cmd_sshp() {
    local project="$1"
    [[ -z "$project" ]] && { echo "Usage: gcptool sshp <project>"; return 1; }
    
    print_header "SSH to All Publishers in $project"
    local publishers=$(_get_instances_by_type "$project" "publish")
    _ssh_multiple "$project" $publishers
}

# SSHD - SSH to all Dispatchers (like AMSTOOL sshd)
cmd_sshd() {
    local project="$1"
    [[ -z "$project" ]] && { echo "Usage: gcptool sshd <project>"; return 1; }
    
    print_header "SSH to All Dispatchers in $project"
    local dispatchers=$(_get_instances_by_type "$project" "dispatcher")
    _ssh_multiple "$project" $dispatchers
}

# SSHPD - SSH to all Publishers and Dispatchers (like AMSTOOL sshpd)
cmd_sshpd() {
    local project="$1"
    [[ -z "$project" ]] && { echo "Usage: gcptool sshpd <project>"; return 1; }
    
    print_header "SSH to All Publishers & Dispatchers in $project"
    local publishers=$(_get_instances_by_type "$project" "publish")
    local dispatchers=$(_get_instances_by_type "$project" "dispatcher")
    _ssh_multiple "$project" $publishers $dispatchers
}

# SSHAEM - SSH to all AEM hosts (Authors + Publishers) (like AMSTOOL sshaem)
cmd_sshaem() {
    local project="$1"
    [[ -z "$project" ]] && { echo "Usage: gcptool sshaem <project>"; return 1; }
    
    print_header "SSH to All AEM Hosts (Authors + Publishers) in $project"
    local authors=$(_get_instances_by_type "$project" "author")
    local publishers=$(_get_instances_by_type "$project" "publish")
    _ssh_multiple "$project" $authors $publishers
}

# SSHX - SSH to all hosts (opens multiple terminal tabs on macOS)
cmd_sshx() {
    local project="$1"
    local filter="${2:-}"
    [[ -z "$project" ]] && { echo "Usage: gcptool sshx <project> [filter]"; return 1; }
    
    print_header "SSH to All Hosts in $project"
    
    local instances
    if [[ -n "$filter" ]]; then
        instances=$(_get_instances_raw "$project" | grep -i "$filter" | grep ",RUNNING," | cut -d',' -f1)
    else
        instances=$(_get_instances_raw "$project" | grep ",RUNNING," | cut -d',' -f1)
    fi
    
    _ssh_multiple "$project" $instances
}

# Helper to open multiple SSH sessions
_ssh_multiple() {
    local project="$1"
    shift
    local instances=("$@")
    
    if [[ ${#instances[@]} -eq 0 ]]; then
        print_info "No matching instances found"
        return 1
    fi
    
    echo "Will open SSH to:"
    for inst in "${instances[@]}"; do
        echo "  - $inst"
    done
    echo ""
    
    if ! confirm_action; then
        return 0
    fi
    
    # On macOS, open new Terminal tabs
    if [[ "$(uname -s)" == "Darwin" ]]; then
        for inst in "${instances[@]}"; do
            local zone=$(_get_zone "$project" "$inst")
            osascript -e "tell application \"Terminal\" to do script \"gcloud compute ssh $inst --project=$project --zone=$zone --tunnel-through-iap\""
        done
        print_success "Opened ${#instances[@]} SSH sessions in new tabs"
    else
        # On Linux, show the commands to run
        print_info "Run these commands in separate terminals:"
        for inst in "${instances[@]}"; do
            local zone=$(_get_zone "$project" "$inst")
            echo "gcloud compute ssh $inst --project=$project --zone=$zone --tunnel-through-iap"
        done
    fi
}

#-------------------------------------------------------------------------------
# CMD - Run Command on Remote Host (like AMSTOOL cmd)
# Usage: gcptool cmd <instance> <command>  OR  gcptool cmd <project> <instance> <command>
#-------------------------------------------------------------------------------

cmd_cmd() {
    local arg1="$1"
    local arg2="$2"
    shift 2 2>/dev/null || true
    local remaining="$*"
    
    if [[ -z "$arg1" ]]; then
        echo -e "${YELLOW}Usage: gcptool cmd <instance> <command>${NC}"
        echo -e "${DIM}Example: gcptool cmd qiddiya-dev-author1mecentral2 'uname -a'${NC}"
        return 1
    fi
    
    local result project instance zone remote_cmd
    
    # Check if arg2 looks like a command (contains spaces or special chars) or an instance
    if [[ "$arg2" =~ [[:space:]] || -z "$remaining" ]]; then
        # arg1 is instance, arg2+ is command
        result=$(_resolve_instance "$arg1" "")
        remote_cmd="$arg2 $remaining"
    else
        # arg1 is project, arg2 is instance, remaining is command
        result=$(_resolve_instance "$arg1" "$arg2")
        remote_cmd="$remaining"
    fi
    
    if [[ -z "$result" ]]; then
        print_error "Could not find instance"
        return 1
    fi
    
    IFS=':' read -r project instance zone <<< "$result"
    
    if [[ -z "$remote_cmd" ]]; then
        echo -e "${YELLOW}Usage: gcptool cmd <instance> <command>${NC}"
        return 1
    fi
    
    print_info "Running on $instance: $remote_cmd"
    gcloud compute ssh "$instance" \
        --project="$project" \
        --zone="$zone" \
        --tunnel-through-iap \
        --command="$remote_cmd"
}

# Run command on multiple instances
cmd_cmdx() {
    local project="$1"
    local filter="$2"
    shift 2 2>/dev/null || true
    local remote_cmd="$*"
    
    if [[ -z "$project" || -z "$filter" || -z "$remote_cmd" ]]; then
        echo -e "${YELLOW}Usage: gcptool cmdx <project> <filter> <command>${NC}"
        echo -e "${DIM}Example: gcptool cmdx adbe-gcp0766 author 'uptime'${NC}"
        return 1
    fi
    
    print_header "Running command on matching instances"
    
    local instances=$(_get_instances_raw "$project" | grep -i "$filter" | grep ",RUNNING," | cut -d',' -f1)
    
    for inst in $instances; do
        local zone=$(_get_zone "$project" "$inst")
        echo -e "\n${BOLD}${CYAN}[$inst]${NC}"
        gcloud compute ssh "$inst" \
            --project="$project" \
            --zone="$zone" \
            --tunnel-through-iap \
            --command="$remote_cmd" 2>/dev/null || print_error "Failed on $inst"
    done
}

#-------------------------------------------------------------------------------
# SCP - Upload/Download Files (like AMSTOOL scp)
#-------------------------------------------------------------------------------

cmd_scp() {
    local direction="$1"  # upload or download
    local project="$2"
    local instance="$3"
    local source="$4"
    local dest="$5"
    
    if [[ -z "$direction" || -z "$project" || -z "$instance" || -z "$source" ]]; then
        echo -e "${YELLOW}Usage:${NC}"
        echo "  gcptool scp upload <project> <instance> <local_file> [remote_path]"
        echo "  gcptool scp download <project> <instance> <remote_file> [local_path]"
        echo ""
        echo -e "${DIM}Examples:${NC}"
        echo "  gcptool scp upload adbe-gcp0766 my-vm ./file.txt /tmp/"
        echo "  gcptool scp download adbe-gcp0766 my-vm /var/log/error.log ./"
        return 1
    fi
    
    local zone=$(_get_zone "$project" "$instance")
    
    if [[ -z "$zone" ]]; then
        print_error "Could not find instance '$instance'"
        return 1
    fi
    
    case "$direction" in
        upload|up|put)
            dest="${dest:-/tmp/}"
            print_info "Uploading $source to $instance:$dest"
            gcloud compute scp "$source" "$instance:$dest" \
                --project="$project" \
                --zone="$zone" \
                --tunnel-through-iap
            ;;
        download|down|get)
            dest="${dest:-.}"
            print_info "Downloading $instance:$source to $dest"
            gcloud compute scp "$instance:$source" "$dest" \
                --project="$project" \
                --zone="$zone" \
                --tunnel-through-iap
            ;;
        *)
            print_error "Invalid direction: $direction (use upload or download)"
            return 1
            ;;
    esac
}

#-------------------------------------------------------------------------------
# URL - Open Browser to Host URL (like AMSTOOL url)
# Usage: gcptool url <instance> [path]  OR  gcptool url <project> <instance> [path]
#-------------------------------------------------------------------------------

cmd_url() {
    local arg1="$1"
    local arg2="$2"
    local arg3="$3"
    
    if [[ -z "$arg1" ]]; then
        echo -e "${YELLOW}Usage: gcptool url <instance> [path]${NC}"
        echo -e "${DIM}Example: gcptool url qiddiya-dev-author1mecentral2 /crx/de${NC}"
        return 1
    fi
    
    local result project instance zone path
    
    # Try to resolve - if arg2 looks like a path, arg1 is instance
    if [[ "$arg2" =~ ^/ || -z "$arg2" ]]; then
        result=$(_resolve_instance "$arg1" "")
        path="${arg2:-/}"
    else
        result=$(_resolve_instance "$arg1" "$arg2")
        path="${arg3:-/}"
    fi
    
    if [[ -z "$result" ]]; then
        print_error "Could not find instance '$arg1'"
        return 1
    fi
    
    IFS=':' read -r project instance zone <<< "$result"
    
    local ip=$(_get_ip_fast "$project" "$instance" "external")
    
    if [[ -z "$ip" || "$ip" == "-" ]]; then
        ip=$(_get_ip_fast "$project" "$instance" "internal")
    fi
    
    if [[ -z "$ip" ]]; then
        print_error "Could not get IP for $instance"
        return 1
    fi
    
    local url="https://${ip}${path}"
    
    print_info "Opening: $url"
    
    case "$(uname -s)" in
        Darwin) open "$url" ;;
        Linux) xdg-open "$url" 2>/dev/null ;;
        *) echo "Open manually: $url" ;;
    esac
}

# AEM - Open AEM Login (shortcut)
# Usage: gcptool aem <instance>
# Only allows author/publish instances (not dispatchers)
cmd_aem() {
    local arg1="$1"
    
    if [[ -z "$arg1" ]]; then
        echo -e "${YELLOW}Usage: gcptool aem <instance>${NC}"
        echo -e "${DIM}Only author and publish instances are allowed (not dispatchers)${NC}"
        return 1
    fi
    
    # Check if it's explicitly a dispatcher
    if [[ "$arg1" =~ [Dd]ispatcher ]]; then
        print_error "Cannot open AEM login on a dispatcher instance"
        print_info "Dispatchers don't run AEM. Use an author or publish instance."
        return 1
    fi
    
    _open_aem_url "$arg1" "/libs/granite/core/content/login.html"
}

# CRX - Open CRX/DE (author/publish only)
cmd_crx() {
    local arg1="$1"
    
    if [[ -z "$arg1" ]]; then
        echo -e "${YELLOW}Usage: gcptool crx <instance>${NC}"
        return 1
    fi
    
    if [[ "$arg1" =~ [Dd]ispatcher ]]; then
        print_error "Cannot open CRX/DE on a dispatcher instance"
        return 1
    fi
    
    # Use aem command's logic but with different path
    _open_aem_url "$arg1" "/crx/de"
}

# CONSOLE - Open Felix Console (author/publish only)
cmd_console() {
    local arg1="$1"
    
    if [[ -z "$arg1" ]]; then
        echo -e "${YELLOW}Usage: gcptool console <instance>${NC}"
        return 1
    fi
    
    if [[ "$arg1" =~ [Dd]ispatcher ]]; then
        print_error "Cannot open Felix Console on a dispatcher instance"
        return 1
    fi
    
    _open_aem_url "$arg1" "/system/console"
}

# Helper function for AEM URL commands (filters dispatchers)
_open_aem_url() {
    local filter="$1"
    local path="$2"
    
    local all_matches=""
    local projects=$(_get_projects)
    
    # First try exact match
    for project in $projects; do
        local match=$(_get_instances_raw "$project" | grep "^${filter}," | grep -iv "dispatcher")
        if [[ -n "$match" ]]; then
            local name=$(echo "$match" | cut -d',' -f1)
            local ext_ip=$(echo "$match" | cut -d',' -f4)
            local int_ip=$(echo "$match" | cut -d',' -f5)
            local ip="${ext_ip:-$int_ip}"
            
            local url="https://${ip}${path}"
            print_info "Opening: $url"
            open "$url" 2>/dev/null || xdg-open "$url" 2>/dev/null || echo "Open: $url"
            return 0
        fi
    done
    
    # Partial match - show selection
    for project in $projects; do
        local matches=$(_get_instances_raw "$project" | grep -i "$filter" | grep -iv "dispatcher")
        if [[ -n "$matches" ]]; then
            while IFS=',' read -r name zone status ext_ip int_ip _; do
                all_matches+="${project}:${name}:${ext_ip}:${int_ip}:${status}"$'\n'
            done <<< "$matches"
        fi
    done
    
    all_matches=$(echo "$all_matches" | sed '/^$/d')
    
    if [[ -z "$all_matches" ]]; then
        print_error "No author/publish instances found matching '$filter'"
        return 1
    fi
    
    local count=$(echo "$all_matches" | wc -l | tr -d ' ')
    
    if [[ "$count" -eq 1 ]]; then
        IFS=':' read -r project name ext_ip int_ip status <<< "$(echo "$all_matches" | head -1)"
        local ip="${ext_ip:-$int_ip}"
        local url="https://${ip}${path}"
        print_info "Opening: $url"
        open "$url" 2>/dev/null || xdg-open "$url" 2>/dev/null || echo "Open: $url"
    else
        echo -e "\n${CYAN}AEM instances matching '$filter':${NC}"
        local i=1
        local selections=()
        while IFS=':' read -r project name ext_ip int_ip status; do
            local status_color="${GREEN}"
            [[ "$status" == "TERMINATED" ]] && status_color="${RED}"
            printf "  %2d) %-45s ${status_color}%-10s${NC} %s\n" "$i" "$name" "$status" "${ext_ip:--}"
            selections+=("${ext_ip:-$int_ip}")
            ((i++))
        done <<< "$all_matches"
        
        echo ""
        read -p "Select [1-$count]: " choice
        
        if [[ "$choice" -ge 1 && "$choice" -le "$count" ]] 2>/dev/null; then
            local ip="${selections[$((choice-1))]}"
            local url="https://${ip}${path}"
            print_info "Opening: $url"
            open "$url" 2>/dev/null || xdg-open "$url" 2>/dev/null || echo "Open: $url"
        else
            print_error "Invalid selection"
            return 1
        fi
    fi
}

#-------------------------------------------------------------------------------
# IP - Get Instance IP
# Usage: gcptool ip <instance>  OR  gcptool ip <project> <instance>
#-------------------------------------------------------------------------------

cmd_ip() {
    local arg1="$1"
    local arg2="$2"
    local arg3="$3"
    
    if [[ -z "$arg1" ]]; then
        echo -e "${YELLOW}Usage: gcptool ip <instance> [external|internal]${NC}"
        return 1
    fi
    
    local result project instance zone ip_type
    
    # Check if arg2 is ip_type or instance
    if [[ "$arg2" == "external" || "$arg2" == "internal" || -z "$arg2" ]]; then
        result=$(_resolve_instance "$arg1" "")
        ip_type="${arg2:-external}"
    else
        result=$(_resolve_instance "$arg1" "$arg2")
        ip_type="${arg3:-external}"
    fi
    
    if [[ -z "$result" ]]; then
        print_error "Could not find instance '$arg1'"
        return 1
    fi
    
    IFS=':' read -r project instance zone <<< "$result"
    
    local ip=$(_get_ip_fast "$project" "$instance" "$ip_type")
    
    if [[ -n "$ip" && "$ip" != "-" ]]; then
        echo "$ip"
    else
        print_error "Could not get $ip_type IP for $instance"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# START/STOP Instances
#-------------------------------------------------------------------------------

cmd_start() {
    local project="$1"
    local force="false"
    shift
    
    local instances=()
    for arg in "$@"; do
        if [[ "$arg" == "--force" || "$arg" == "-f" || "$arg" == "-y" || "$arg" == "--yes" ]]; then
            force="true"
        else
            instances+=("$arg")
        fi
    done
    
    if [[ -z "$project" || ${#instances[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Usage: gcptool start <project> <instance1> [instance2] ... [--force]${NC}"
        return 1
    fi
    
    print_header "Starting ${#instances[@]} Instance(s)"
    
    echo -e "${CYAN}Project:${NC} $project"
    echo -e "${CYAN}Instances to START:${NC}"
    for inst in "${instances[@]}"; do
        local zone=$(_get_zone "$project" "$inst")
        echo -e "  ${GREEN}▶${NC} $inst ${DIM}($zone)${NC}"
    done
    echo ""
    
    if [[ "$force" != "true" ]]; then
        echo -e "${YELLOW}Are you sure you want to START these instances?${NC}"
        if ! confirm_action; then
            print_info "Cancelled"
            return 0
        fi
    fi
    
    echo ""
    local pids=()
    for instance in "${instances[@]}"; do
        local zone=$(_get_zone "$project" "$instance")
        if [[ -n "$zone" ]]; then
            print_info "Starting $instance..."
            gcloud compute instances start "$instance" \
                --project="$project" \
                --zone="$zone" \
                --async 2>/dev/null &
            pids+=($!)
        else
            print_error "Could not find zone for $instance"
        fi
    done
    
    for pid in "${pids[@]}"; do wait "$pid"; done
    
    cache_clear "instances_${project}"
    print_success "Start command sent"
    
    echo ""
    print_info "Waiting for IPs..."
    sleep 5
    for instance in "${instances[@]}"; do
        # Force refresh to get new IP
        local ip=$(gcloud compute instances describe "$instance" \
            --project="$project" \
            --zone="$(_get_zone "$project" "$instance")" \
            --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)
        [[ -n "$ip" ]] && echo -e "  ${GREEN}✓${NC} $instance: ${BOLD}$ip${NC}"
    done
}

cmd_stop() {
    local project="$1"
    local force="false"
    shift
    
    local instances=()
    for arg in "$@"; do
        if [[ "$arg" == "--force" || "$arg" == "-f" || "$arg" == "-y" || "$arg" == "--yes" ]]; then
            force="true"
        else
            instances+=("$arg")
        fi
    done
    
    if [[ -z "$project" || ${#instances[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Usage: gcptool stop <project> <instance1> [instance2] ... [--force]${NC}"
        return 1
    fi
    
    print_header "Stopping ${#instances[@]} Instance(s)"
    
    echo -e "${CYAN}Project:${NC} $project"
    echo -e "${CYAN}Instances to STOP:${NC}"
    for inst in "${instances[@]}"; do
        local zone=$(_get_zone "$project" "$inst")
        local ip=$(_get_ip_fast "$project" "$inst" "external")
        echo -e "  ${RED}■${NC} $inst ${DIM}($zone)${NC} - ${ip:-no external IP}"
    done
    echo ""
    
    if [[ "$force" != "true" ]]; then
        echo -e "${RED}${BOLD}⚠️  WARNING: This will STOP the instance(s)!${NC}"
        echo -e "${RED}   Services will become unavailable.${NC}"
        echo ""
        if ! confirm_action; then
            print_info "Cancelled"
            return 0
        fi
    fi
    
    echo ""
    local pids=()
    for instance in "${instances[@]}"; do
        local zone=$(_get_zone "$project" "$instance")
        if [[ -n "$zone" ]]; then
            print_info "Stopping $instance..."
            gcloud compute instances stop "$instance" \
                --project="$project" \
                --zone="$zone" \
                --async 2>/dev/null &
            pids+=($!)
        fi
    done
    
    for pid in "${pids[@]}"; do wait "$pid"; done
    
    cache_clear "instances_${project}"
    print_success "Stop command sent to all instances"
}

#-------------------------------------------------------------------------------
# SNAPSHOT - Create Disk Snapshot
#-------------------------------------------------------------------------------

cmd_snapshot() {
    local project="$1"
    local disk="$2"
    local zone="$3"
    local snapshot_name="$4"
    
    if [[ -z "$project" || -z "$disk" ]]; then
        echo -e "${YELLOW}Usage: gcptool snapshot <project> <disk> [zone] [snapshot_name]${NC}"
        return 1
    fi
    
    if [[ -z "$zone" ]]; then
        zone=$(gcloud compute disks list \
            --project="$project" \
            --filter="name=$disk" \
            --format="value(zone.basename())" 2>/dev/null | head -1)
    fi
    
    if [[ -z "$snapshot_name" ]]; then
        snapshot_name="${disk}-snap-$(date +%Y%m%d-%H%M%S)"
    fi
    
    print_header "Creating Snapshot"
    print_info "Disk: $disk | Zone: $zone"
    print_info "Snapshot: $snapshot_name"
    
    if gcloud compute disks snapshot "$disk" \
        --project="$project" \
        --zone="$zone" \
        --snapshot-names="$snapshot_name" 2>/dev/null; then
        print_success "Snapshot created: $snapshot_name"
    else
        print_error "Failed to create snapshot"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# LB - Load Balancer Management
#-------------------------------------------------------------------------------

# List all backend services and their backends
cmd_lb_list() {
    local project="$1"
    
    if [[ -z "$project" ]]; then
        # List for all projects
        local projects=$(_get_projects)
        for proj in $projects; do
            echo -e "\n${BOLD}${CYAN}[$proj]${NC}"
            gcloud compute backend-services list \
                --project="$proj" \
                --format="table(name,backends[].group.basename():label=BACKENDS,protocol,loadBalancingScheme:label=SCHEME)" \
                2>/dev/null
        done
    else
        print_header "Backend Services in $project"
        gcloud compute backend-services list \
            --project="$project" \
            --format="table(name,backends[].group.basename():label=BACKENDS,protocol,loadBalancingScheme:label=SCHEME)" \
            2>/dev/null
        
        echo ""
        print_header "Instance Groups in $project"
        gcloud compute instance-groups list \
            --project="$project" \
            --format="table(name,zone.basename(),size:label=INSTANCES)" \
            2>/dev/null
    fi
}

# Show which instance group and backend service an instance belongs to
cmd_lb_status() {
    local arg1="$1"
    local arg2="$2"
    
    if [[ -z "$arg1" ]]; then
        echo -e "${YELLOW}Usage: gcptool lb status <instance>${NC}"
        return 1
    fi
    
    # Resolve instance
    local result=$(_resolve_instance "$arg1" "$arg2")
    
    if [[ -z "$result" ]]; then
        print_error "Could not find instance '$arg1'"
        return 1
    fi
    
    local project instance zone
    IFS=':' read -r project instance zone <<< "$result"
    
    print_header "Load Balancer Status: $instance"
    print_info "Project: $project | Zone: $zone"
    echo ""
    
    # Find which instance group(s) this instance belongs to
    local instance_groups=$(gcloud compute instance-groups list \
        --project="$project" \
        --format="value(name,zone.basename())" 2>/dev/null)
    
    local found_in=""
    while IFS=$'\t' read -r ig_name ig_zone; do
        # Check if instance is in this group
        local members=$(gcloud compute instance-groups list-instances "$ig_name" \
            --project="$project" \
            --zone="$ig_zone" \
            --format="value(instance.basename())" 2>/dev/null)
        
        if echo "$members" | grep -q "^${instance}$"; then
            found_in="$ig_name"
            
            echo -e "${GREEN}✓ Instance is IN the load balancer${NC}"
            echo -e "  Instance Group: ${BOLD}$ig_name${NC}"
            echo -e "  Zone: $ig_zone"
            
            # Find which backend service uses this instance group
            local backend_services=$(gcloud compute backend-services list \
                --project="$project" \
                --format="csv[no-heading](name,backends[].group)" 2>/dev/null)
            
            while IFS=',' read -r bs_name bs_backends; do
                if echo "$bs_backends" | grep -q "$ig_name"; then
                    echo -e "  Backend Service: ${BOLD}$bs_name${NC}"
                fi
            done <<< "$backend_services"
            
            break
        fi
    done <<< "$instance_groups"
    
    if [[ -z "$found_in" ]]; then
        echo -e "${RED}✗ Instance is NOT in any load balancer${NC}"
        echo ""
        echo "Available instance groups in $project:"
        gcloud compute instance-groups list \
            --project="$project" \
            --format="table(name,zone.basename(),size)" 2>/dev/null
    fi
}

# Get list of instance groups for a project (for selection)
_get_instance_groups() {
    local project="$1"
    local filter="${2:-}"
    
    local groups=$(gcloud compute instance-groups list \
        --project="$project" \
        --format="value(name,zone.basename())" 2>/dev/null)
    
    if [[ -n "$filter" ]]; then
        echo "$groups" | grep -i "$filter"
    else
        echo "$groups"
    fi
}

# Interactive instance group selection
_select_instance_group() {
    local project="$1"
    local filter="${2:-}"
    
    local groups
    if [[ -n "$filter" ]]; then
        groups=$(_get_instance_groups "$project" "$filter")
    else
        groups=$(_get_instance_groups "$project")
    fi
    
    if [[ -z "$groups" ]]; then
        print_error "No instance groups found"
        return 1
    fi
    
    # Count matches
    local count=$(echo "$groups" | wc -l | tr -d ' ')
    
    if [[ "$count" -eq 1 ]]; then
        # Only one match, use it
        echo "$groups" | cut -f1
        return 0
    fi
    
    # Multiple matches - show selection
    echo -e "\n${CYAN}Select instance group:${NC}" >&2
    local i=1
    local names=()
    while IFS=$'\t' read -r name zone; do
        echo "  $i) $name ($zone)" >&2
        names+=("$name:$zone")
        ((i++))
    done <<< "$groups"
    
    echo "" >&2
    read -p "Enter choice [1-$count]: " choice
    
    if [[ "$choice" -ge 1 && "$choice" -le "$count" ]]; then
        echo "${names[$((choice-1))]}"
    else
        print_error "Invalid selection" >&2
        return 1
    fi
}

# Disable (remove) instance from load balancer
cmd_lb_disable() {
    local arg1="$1"
    local arg2="$2"
    
    if [[ -z "$arg1" ]]; then
        echo -e "${YELLOW}Usage: gcptool lb disable <instance>${NC}"
        return 1
    fi
    
    # Resolve instance
    local result=$(_resolve_instance "$arg1" "$arg2")
    
    if [[ -z "$result" ]]; then
        print_error "Could not find instance '$arg1'"
        return 1
    fi
    
    local project instance zone
    IFS=':' read -r project instance zone <<< "$result"
    
    print_header "Disable Instance from Load Balancer"
    print_info "Instance: $instance"
    print_info "Project: $project"
    
    # Find which instance group this instance is in
    local instance_groups=$(gcloud compute instance-groups list \
        --project="$project" \
        --format="value(name,zone.basename())" 2>/dev/null)
    
    local found_ig=""
    local found_zone=""
    
    while IFS=$'\t' read -r ig_name ig_zone; do
        local members=$(gcloud compute instance-groups list-instances "$ig_name" \
            --project="$project" \
            --zone="$ig_zone" \
            --format="value(instance.basename())" 2>/dev/null)
        
        if echo "$members" | grep -q "^${instance}$"; then
            found_ig="$ig_name"
            found_zone="$ig_zone"
            break
        fi
    done <<< "$instance_groups"
    
    if [[ -z "$found_ig" ]]; then
        print_error "Instance '$instance' is not in any instance group"
        return 1
    fi
    
    echo -e "Instance Group: ${BOLD}$found_ig${NC}"
    echo -e "Zone: $found_zone"
    echo ""
    
    # Confirmation
    echo -e "${RED}${BOLD}⚠️  WARNING: This will remove the instance from the load balancer!${NC}"
    echo -e "${RED}   Traffic will stop being routed to this dispatcher.${NC}"
    echo ""
    
    if ! confirm_action; then
        print_info "Cancelled"
        return 0
    fi
    
    # Get the full instance URL
    local instance_url="zones/${found_zone}/instances/${instance}"
    
    echo ""
    print_info "Removing $instance from $found_ig..."
    
    if gcloud compute instance-groups unmanaged remove-instances "$found_ig" \
        --project="$project" \
        --zone="$found_zone" \
        --instances="$instance" 2>/dev/null; then
        print_success "Instance removed from load balancer"
        echo ""
        echo -e "${DIM}To add back, run:${NC}"
        echo -e "  gcptool lb enable $instance $found_ig"
    else
        print_error "Failed to remove instance from load balancer"
        return 1
    fi
}

# Enable (add) instance to load balancer
cmd_lb_enable() {
    local instance_arg="$1"
    local ig_arg="$2"
    
    if [[ -z "$instance_arg" ]]; then
        echo -e "${YELLOW}Usage: gcptool lb enable <instance> [instance-group]${NC}"
        echo -e "${DIM}If instance-group is not specified or partial, you'll be prompted to select.${NC}"
        return 1
    fi
    
    # Resolve instance
    local result=$(_resolve_instance "$instance_arg" "")
    
    if [[ -z "$result" ]]; then
        print_error "Could not find instance '$instance_arg'"
        return 1
    fi
    
    local project instance zone
    IFS=':' read -r project instance zone <<< "$result"
    
    print_header "Enable Instance in Load Balancer"
    print_info "Instance: $instance"
    print_info "Project: $project"
    print_info "Zone: $zone"
    echo ""
    
    # Select or find instance group
    local ig_name ig_zone
    
    if [[ -z "$ig_arg" ]]; then
        # No instance group specified - show selection
        echo "Select which instance group to add the dispatcher to:"
        local selected=$(_select_instance_group "$project")
        if [[ -z "$selected" ]]; then
            return 1
        fi
        IFS=':' read -r ig_name ig_zone <<< "$selected"
    else
        # Instance group specified (full or partial)
        local matches=$(_get_instance_groups "$project" "$ig_arg")
        local count=$(echo "$matches" | grep -c . || echo 0)
        
        if [[ "$count" -eq 0 ]]; then
            print_error "No instance groups matching '$ig_arg'"
            return 1
        elif [[ "$count" -eq 1 ]]; then
            IFS=$'\t' read -r ig_name ig_zone <<< "$matches"
        else
            echo "Multiple instance groups match '$ig_arg':"
            local selected=$(_select_instance_group "$project" "$ig_arg")
            if [[ -z "$selected" ]]; then
                return 1
            fi
            IFS=':' read -r ig_name ig_zone <<< "$selected"
        fi
    fi
    
    echo -e "Instance Group: ${BOLD}$ig_name${NC}"
    echo -e "Instance Group Zone: $ig_zone"
    echo ""
    
    # Check if instance is already in the group
    local members=$(gcloud compute instance-groups list-instances "$ig_name" \
        --project="$project" \
        --zone="$ig_zone" \
        --format="value(instance.basename())" 2>/dev/null)
    
    if echo "$members" | grep -q "^${instance}$"; then
        print_info "Instance is already in this instance group"
        return 0
    fi
    
    # Confirmation
    echo -e "${YELLOW}${BOLD}This will add the instance to the load balancer.${NC}"
    echo -e "${YELLOW}Traffic will start being routed to this dispatcher.${NC}"
    echo ""
    
    if ! confirm_action; then
        print_info "Cancelled"
        return 0
    fi
    
    echo ""
    print_info "Adding $instance to $ig_name..."
    
    if gcloud compute instance-groups unmanaged add-instances "$ig_name" \
        --project="$project" \
        --zone="$ig_zone" \
        --instances="$instance" 2>/dev/null; then
        print_success "Instance added to load balancer"
    else
        print_error "Failed to add instance to load balancer"
        return 1
    fi
}

# Main LB command dispatcher
cmd_lb() {
    local subcommand="$1"
    shift 2>/dev/null || true
    
    case "$subcommand" in
        list|ls)
            cmd_lb_list "$@"
            ;;
        status|st)
            cmd_lb_status "$@"
            ;;
        disable|dis|remove|rm)
            cmd_lb_disable "$@"
            ;;
        enable|en|add)
            cmd_lb_enable "$@"
            ;;
        *)
            echo -e "${BOLD}Load Balancer Commands:${NC}"
            echo ""
            echo "  gcptool lb list [project]           List all backends and instance groups"
            echo "  gcptool lb status <instance>        Show which LB an instance is in"
            echo "  gcptool lb disable <instance>       Remove instance from LB"
            echo "  gcptool lb enable <instance> [group] Add instance to LB"
            echo ""
            echo -e "${DIM}Examples:${NC}"
            echo "  gcptool lb list adbe-gcp0766"
            echo "  gcptool lb status qiddiya-prod-dispatcher1mecentral2"
            echo "  gcptool lb disable qiddiya-prod-dispatcher1mecentral2"
            echo "  gcptool lb enable qiddiya-prod-dispatcher1mecentral2 qiddiya-prod"
            ;;
    esac
}

#-------------------------------------------------------------------------------
# INFO - Display Information (like AMSTOOL info)
# Usage: gcptool info <instance>  OR  gcptool info <project> <instance>
#-------------------------------------------------------------------------------

cmd_info() {
    local arg1="$1"
    local arg2="$2"
    
    if [[ -z "$arg1" ]]; then
        echo -e "${YELLOW}Usage: gcptool info <instance>${NC}"
        return 1
    fi
    
    local result=$(_resolve_instance "$arg1" "$arg2")
    
    if [[ -z "$result" ]]; then
        print_error "Could not find instance '$arg1'"
        return 1
    fi
    
    local project instance zone
    IFS=':' read -r project instance zone <<< "$result"
    
    print_header "Instance Info: $instance"
    print_info "Project: $project | Zone: $zone"
    echo ""
    
    gcloud compute instances describe "$instance" \
        --project="$project" \
        --zone="$zone" \
        --format="yaml(name,status,machineType.basename(),zone.basename(),networkInterfaces[0].networkIP,networkInterfaces[0].accessConfigs[0].natIP,disks[].source.basename(),metadata.items,labels)" \
        2>/dev/null
}

#-------------------------------------------------------------------------------
# STATUS - Quick Status (all projects)
#-------------------------------------------------------------------------------

cmd_status() {
    print_header "Quick Status - All Projects"
    
    local projects=$(_get_projects)
    
    for project in $projects; do
        echo -e "\n${BOLD}${CYAN}[$project]${NC}"
        local data=$(_get_instances_raw "$project")
        
        if [[ -n "$data" ]]; then
            local running=$(echo "$data" | grep ",RUNNING," | wc -l | tr -d ' ')
            local stopped=$(echo "$data" | grep ",TERMINATED," | wc -l | tr -d ' ')
            local authors=$(echo "$data" | grep -i "author" | grep ",RUNNING," | wc -l | tr -d ' ')
            local publishers=$(echo "$data" | grep -i "publish" | grep ",RUNNING," | wc -l | tr -d ' ')
            local dispatchers=$(echo "$data" | grep -i "dispatcher" | grep ",RUNNING," | wc -l | tr -d ' ')
            
            echo -e "  ${GREEN}Running: $running${NC}  ${RED}Stopped: $stopped${NC}"
            echo -e "  ${DIM}Authors: $authors | Publishers: $publishers | Dispatchers: $dispatchers${NC}"
        fi
    done
}

#-------------------------------------------------------------------------------
# SEARCH - Search Instances
#-------------------------------------------------------------------------------

cmd_search() {
    local pattern="$1"
    
    if [[ -z "$pattern" ]]; then
        echo -e "${YELLOW}Usage: gcptool search <pattern>${NC}"
        return 1
    fi
    
    print_header "Searching for: $pattern"
    
    local projects=$(_get_projects)
    
    for project in $projects; do
        local matches=$(_get_instances_raw "$project" | grep -i "$pattern")
        if [[ -n "$matches" ]]; then
            echo -e "\n${BOLD}${CYAN}[$project]${NC}"
            echo "$matches" | while IFS=',' read -r name zone status ext_ip int_ip _; do
                local status_color="$GREEN"
                [[ "$status" == "TERMINATED" ]] && status_color="$RED"
                printf "  %-40s ${status_color}%-12s${NC} %s\n" "$name" "$status" "${ext_ip:--}"
            done
        fi
    done
}

#-------------------------------------------------------------------------------
# Interactive Menu
#-------------------------------------------------------------------------------

show_menu() {
    while true; do
        print_header "GCPTOOL - GCP Compute Engine Toolkit"
        echo -e "${BOLD}Select an operation:${NC}\n"
        echo "  ${CYAN}LIST${NC}"
        echo "   1) List projects          2) List instances"
        echo "   3) List snapshots         4) List disks"
        echo ""
        echo "  ${CYAN}SSH (like AMSTOOL)${NC}"
        echo "   5) ssh   - SSH to instance"
        echo "   6) ssha  - SSH to all Authors"
        echo "   7) sshp  - SSH to all Publishers"
        echo "   8) sshd  - SSH to all Dispatchers"
        echo "   9) sshpd - SSH to all Pub/Disp"
        echo "  10) sshaem - SSH to all AEM (Author+Pub)"
        echo ""
        echo "  ${CYAN}COMMANDS${NC}"
        echo "  11) Run command           12) Upload/Download files"
        echo ""
        echo "  ${CYAN}BROWSER${NC}"
        echo "  13) Open AEM login        14) Open CRX/DE"
        echo "  15) Open Felix Console    16) Open custom URL"
        echo ""
        echo "  ${CYAN}MANAGE${NC}"
        echo "  17) Start instance(s)     18) Stop instance(s)"
        echo "  19) Create snapshot       20) Get instance info"
        echo ""
        echo "  ${CYAN}UTILITIES${NC}"
        echo "  21) Quick status          22) Search instances"
        echo "  23) Update cache          24) Clear cache"
        echo ""
        echo "   q) Quit"
        echo ""
        read -p "Enter choice: " choice
        
        case $choice in
            1) cmd_list projects ;;
            2) read -p "Project: " p; cmd_list instances "$p" ;;
            3) read -p "Project: " p; cmd_list snapshots "$p" ;;
            4) read -p "Project: " p; cmd_list disks "$p" ;;
            5) read -p "Project: " p; read -p "Instance: " i; cmd_ssh "$p" "$i" ;;
            6) read -p "Project: " p; cmd_ssha "$p" ;;
            7) read -p "Project: " p; cmd_sshp "$p" ;;
            8) read -p "Project: " p; cmd_sshd "$p" ;;
            9) read -p "Project: " p; cmd_sshpd "$p" ;;
            10) read -p "Project: " p; cmd_sshaem "$p" ;;
            11) read -p "Project: " p; read -p "Instance: " i; read -p "Command: " c; cmd_cmd "$p" "$i" "$c" ;;
            12) read -p "Direction (upload/download): " d; read -p "Project: " p; read -p "Instance: " i; read -p "Source: " s; read -p "Dest: " dest; cmd_scp "$d" "$p" "$i" "$s" "$dest" ;;
            13) read -p "Project: " p; read -p "Instance: " i; cmd_aem "$p" "$i" ;;
            14) read -p "Project: " p; read -p "Instance: " i; cmd_crx "$p" "$i" ;;
            15) read -p "Project: " p; read -p "Instance: " i; cmd_console "$p" "$i" ;;
            16) read -p "Project: " p; read -p "Instance: " i; read -p "Path: " path; cmd_url "$p" "$i" "$path" ;;
            17) read -p "Project: " p; read -p "Instance(s): " -a insts; cmd_start "$p" "${insts[@]}" ;;
            18) read -p "Project: " p; read -p "Instance(s): " -a insts; cmd_stop "$p" "${insts[@]}" ;;
            19) read -p "Project: " p; read -p "Disk: " d; cmd_snapshot "$p" "$d" ;;
            20) read -p "Project: " p; read -p "Instance: " i; cmd_info "$p" "$i" ;;
            21) cmd_status ;;
            22) read -p "Pattern: " pat; cmd_search "$pat" ;;
            23) cache_update ;;
            24) cache_clear ;;
            q|Q) exit 0 ;;
            *) print_error "Invalid option" ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

#-------------------------------------------------------------------------------
# Documentation
#-------------------------------------------------------------------------------

show_manual() {
    local manual_file="$SCRIPT_DIR/MANUAL.md"
    if [[ -f "$manual_file" ]]; then
        if command -v less &>/dev/null; then
            less "$manual_file"
        else
            cat "$manual_file"
        fi
    else
        print_error "Manual not found"
    fi
}

show_cheatsheet() {
    local cheat_file="$SCRIPT_DIR/CHEATSHEET.md"
    if [[ -f "$cheat_file" ]]; then
        cat "$cheat_file"
    else
        print_error "Cheatsheet not found"
    fi
}

show_help() {
    cat << 'EOF'
GCPTOOL - GCP Compute Engine Toolkit
Created by Diana Adascalitei, Dec 2025

USAGE:
    gcptool <command> [options]

LIST COMMANDS:
    list projects               List all GCP projects
    list instances [filter]     List instances (e.g., qiddiya-prod)
    list snapshots <filter>     List snapshots for instance/prefix
    list disks <filter>         List disks for instance/prefix

SSH COMMANDS:
    ssh <instance>              SSH to instance (auto-finds project)
    ssha <project>              SSH to all Authors
    sshp <project>              SSH to all Publishers  
    sshd <project>              SSH to all Dispatchers
    sshpd <project>             SSH to all Publishers & Dispatchers
    sshaem <project>            SSH to all AEM (Authors + Publishers)
    sshx <project> [filter]     SSH to all matching hosts

REMOTE COMMANDS:
    cmd <instance> <command>    Run command on instance
    cmdx <project> <filter> <cmd> Run command on matching instances
    scp upload <proj> <inst> <local> [remote]   Upload file
    scp download <proj> <inst> <remote> [local] Download file

BROWSER (URL) COMMANDS:
    url <instance> [path]       Open URL in browser
    aem <instance>              Open AEM login page
    crx <instance>              Open CRX/DE
    console <instance>          Open Felix Console

INSTANCE MANAGEMENT:
    start <project> <inst...>   Start instance(s) in parallel
    stop <project> <inst...>    Stop instance(s)
    snapshot <project> <disk>   Create disk snapshot
    info <instance>             Show instance details
    ip <instance>               Get instance IP

LOAD BALANCER:
    lb list [project]           List backends and instance groups
    lb status <instance>        Show which LB an instance is in
    lb disable <instance>       Remove instance from LB
    lb enable <instance> [group] Add instance to LB (with selection)

UTILITIES:
    status                      Quick status all projects
    search <pattern>            Search instances by name
    cache                       Update cache
    cache-clear                 Clear cache
    menu                        Interactive menu
    man                         View full manual
    cheat                       View cheatsheet

NOTE: Most commands auto-detect the project! Just use the instance name.

EXAMPLES:
    gcptool ssh qiddiya-dev-author1mecentral2
    gcptool aem qiddiya-prod-author1mecentral2
    gcptool ip qiddiya-dev-author1mecentral2
    gcptool cmd qiddiya-dev-author1mecentral2 'uptime'
    gcptool ssha adbe-gcp0766
    gcptool search author
    gcptool status

EOF
}

#-------------------------------------------------------------------------------
# Main Entry Point
#-------------------------------------------------------------------------------

main() {
    local command="${1:-menu}"
    shift 2>/dev/null || true
    
    case "$command" in
        # List commands
        list|ls) cmd_list "$@" ;;
        projects) cmd_list projects ;;
        instances|vms) cmd_list instances "$@" ;;
        snapshots) cmd_list snapshots "$@" ;;
        disks) cmd_list disks "$@" ;;
        
        # SSH commands (AMSTOOL style)
        ssh) cmd_ssh "$@" ;;
        ssha) cmd_ssha "$@" ;;
        sshp) cmd_sshp "$@" ;;
        sshd) cmd_sshd "$@" ;;
        sshpd) cmd_sshpd "$@" ;;
        sshaem) cmd_sshaem "$@" ;;
        sshx) cmd_sshx "$@" ;;
        
        # Remote commands
        cmd) cmd_cmd "$@" ;;
        cmdx) cmd_cmdx "$@" ;;
        scp|cp) cmd_scp "$@" ;;
        
        # Browser/URL commands
        url) cmd_url "$@" ;;
        aem) cmd_aem "$@" ;;
        crx) cmd_crx "$@" ;;
        console) cmd_console "$@" ;;
        
        # Instance management
        start) cmd_start "$@" ;;
        stop) cmd_stop "$@" ;;
        snapshot|snap) cmd_snapshot "$@" ;;
        info) cmd_info "$@" ;;
        ip) cmd_ip "$@" ;;
        
        # Load balancer management
        lb) cmd_lb "$@" ;;
        
        # Utilities
        status) cmd_status ;;
        search|find) cmd_search "$@" ;;
        cache) cache_update ;;
        cache-clear|clear) cache_clear ;;
        
        # Documentation
        menu) show_menu ;;
        man|manual) show_manual ;;
        cheat|cheatsheet) show_cheatsheet ;;
        help|--help|-h) show_help ;;
        
        *) print_error "Unknown: $command"; show_help; exit 1 ;;
    esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
