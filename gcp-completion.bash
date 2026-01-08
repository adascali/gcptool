#!/bin/bash
#===============================================================================
# Bash/Zsh Completion for GCP Tools
# Add to your .bashrc or .zshrc:
#   source /Users/adascali/gcp-automation/gcp-completion.bash
#===============================================================================

_gcp_tools_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    local cmd="${COMP_WORDS[1]}"
    
    # Commands
    local commands="projects instances ip ssh start stop snapshot snapshots aem status search cache-clear menu help"
    
    # Cache directory
    local cache_dir="$HOME/.gcp-tools/cache"
    
    case "$COMP_CWORD" in
        1)
            # Complete commands
            COMPREPLY=($(compgen -W "$commands" -- "$cur"))
            ;;
        2)
            # Complete project names for commands that need them
            case "$cmd" in
                instances|ip|ssh|start|stop|snapshot|snapshots|aem)
                    if [[ -f "$cache_dir/projects.cache" ]]; then
                        local projects=$(cat "$cache_dir/projects.cache" 2>/dev/null)
                        COMPREPLY=($(compgen -W "$projects" -- "$cur"))
                    else
                        # Fallback to gcloud
                        local projects=$(gcloud projects list --format="value(projectId)" 2>/dev/null)
                        COMPREPLY=($(compgen -W "$projects" -- "$cur"))
                    fi
                    ;;
            esac
            ;;
        3)
            # Complete instance names for commands that need them
            local project="${COMP_WORDS[2]}"
            case "$cmd" in
                ip|ssh|start|stop|aem)
                    if [[ -f "$cache_dir/instances_${project}.cache" ]]; then
                        local instances=$(cat "$cache_dir/instances_${project}.cache" 2>/dev/null | cut -d',' -f1)
                        COMPREPLY=($(compgen -W "$instances" -- "$cur"))
                    fi
                    ;;
                snapshot)
                    # Complete disk names
                    local disks=$(gcloud compute disks list --project="$project" --format="value(name)" 2>/dev/null)
                    COMPREPLY=($(compgen -W "$disks" -- "$cur"))
                    ;;
            esac
            ;;
        *)
            # For start/stop, allow multiple instances
            local project="${COMP_WORDS[2]}"
            case "$cmd" in
                start|stop)
                    if [[ -f "$cache_dir/instances_${project}.cache" ]]; then
                        local instances=$(cat "$cache_dir/instances_${project}.cache" 2>/dev/null | cut -d',' -f1)
                        COMPREPLY=($(compgen -W "$instances --force" -- "$cur"))
                    fi
                    ;;
            esac
            ;;
    esac
}

# Register completions
complete -F _gcp_tools_completions gcp-tools.sh
complete -F _gcp_tools_completions ./gcp-tools.sh
complete -F _gcp_tools_completions gcptool

# Zsh compatibility
if [[ -n "$ZSH_VERSION" ]]; then
    autoload -U +X bashcompinit && bashcompinit
    complete -F _gcp_tools_completions gcp-tools.sh
    complete -F _gcp_tools_completions gcptool
fi

