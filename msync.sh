#!/bin/bash
# msync - Multi-Host Synchronization Tool
# Version: 1.7.0
# Description: Synchronize files/directories to multiple hosts simultaneously
# Author: Your Name
# License: MIT

# Ensure compatible behavior in different shells
if [ -n "$ZSH_VERSION" ]; then
    # Running in ZSH
    emulate -L sh
    setopt SH_WORD_SPLIT
fi

# Script version
VERSION="1.5.0"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/msync"
HOSTGROUPS_FILE="$CONFIG_DIR/hostgroups"

# Get default user from environment or fallback to root
DEFAULT_USER="${MSYNC_DEFAULT_USER:-root}"
DEFAULT_PARALLEL="${MSYNC_PARALLEL_DEFAULT:-3}"
DEFAULT_SSH_PORT="${MSYNC_SSH_PORT:-22}"
DEBUG_MODE="${MSYNC_DEBUG:-0}"

# Check if running in debug mode
if [ "$DEBUG_MODE" = "1" ]; then
    set -x  # Enable command tracing
fi

# Function to check required dependencies
check_dependencies() {
    local missing_deps=""
    
    # Check for rsync
    if ! command -v rsync >/dev/null 2>&1; then
        missing_deps="rsync"
    fi
    
    # Check for ssh
    if ! command -v ssh >/dev/null 2>&1; then
        [ -n "$missing_deps" ] && missing_deps="$missing_deps, ssh" || missing_deps="ssh"
    fi
    
    if [ -n "$missing_deps" ]; then
        echo "Missing dependencies: $missing_deps"
        echo "Run 'msync --dependencies' to install them automatically"
        return 1
    fi
    
    return 0
}

# Function to install dependencies
install_dependencies() {
    echo "Checking for required dependencies..."
    
    local need_rsync=0
    local need_ssh=0
    
    # Check what's missing
    if ! command -v rsync >/dev/null 2>&1; then
        echo "rsync: Not found"
        need_rsync=1
    else
        echo "rsync: Found"
    fi
    
    if ! command -v ssh >/dev/null 2>&1; then
        echo "ssh: Not found"
        need_ssh=1
    else
        echo "ssh: Found"
    fi
    
    if [ $need_rsync -eq 0 ] && [ $need_ssh -eq 0 ]; then
        echo "All dependencies are already installed."
        return 0
    fi
    
    # Detect package manager
    local pkg_manager=""
    local install_cmd=""
    local ssh_pkg="openssh-client"
    
    if command -v apt-get >/dev/null 2>&1; then
        pkg_manager="apt-get"
        install_cmd="apt-get install -y"
    elif command -v dnf >/dev/null 2>&1; then
        pkg_manager="dnf"
        install_cmd="dnf install -y"
        ssh_pkg="openssh-clients"
    elif command -v yum >/dev/null 2>&1; then
        pkg_manager="yum"
        install_cmd="yum install -y"
        ssh_pkg="openssh-clients"
    elif command -v apk >/dev/null 2>&1; then
        pkg_manager="apk"
        install_cmd="apk add"
        ssh_pkg="openssh"
    elif command -v pacman >/dev/null 2>&1; then
        pkg_manager="pacman"
        install_cmd="pacman -S --noconfirm"
        ssh_pkg="openssh"
    elif command -v brew >/dev/null 2>&1; then
        pkg_manager="brew"
        install_cmd="brew install"
        ssh_pkg="openssh"
    elif command -v zypper >/dev/null 2>&1; then
        pkg_manager="zypper"
        install_cmd="zypper install -y"
    else
        echo "Unable to detect package manager. Please install dependencies manually."
        return 1
    fi
    
    echo "Detected package manager: $pkg_manager"
    
    # Install missing packages
    if [ $need_rsync -eq 1 ]; then
        echo "Installing rsync using $pkg_manager..."
        if ! sudo "$install_cmd" rsync; then
            echo "Failed to install rsync. Please install it manually."
            return 1
        fi
    fi
    
    if [ $need_ssh -eq 1 ]; then
        echo "Installing SSH using $pkg_manager..."
        if ! sudo "$install_cmd" "$ssh_pkg"; then
            echo "Failed to install SSH. Please install it manually."
            return 1
        fi
    fi
    
    echo "Dependencies installed successfully."
    return 0
}

# Function to display help
show_help() {
    echo "msync - Multi-host synchronization tool"
    echo
    echo "USAGE:"
    echo "    msync [OPTIONS] [SOURCE] [DESTINATION] [HOSTS]"
    echo
    echo "OPTIONS:"
    echo "    -h, --help         Show help"
    echo "    -v, --version      Show version"
    echo "    -i, --interactive  Force interactive mode"
    echo "    -q, --quiet        Minimal output"
    echo "    -n, --dry-run      Test run without making changes"
    echo "    -f, --force        Skip connection tests"
    echo "    -r, --recursive    Recursive directory copy"
    echo "    -p, --port PORT    Custom SSH port (default: $DEFAULT_SSH_PORT)"
    echo "    -l, --limit RATE   Limit bandwidth (e.g., 1000k)"
    echo "    -e, --exclude PAT  Exclude files matching pattern"
    echo "    -P, --parallel N   Run N transfers in parallel (default: $DEFAULT_PARALLEL)"
    echo "    -m, --mkdir        Create destination directory if missing"
    echo "    -u, --user USER    Remote username (default: $DEFAULT_USER)"
    echo "    -d, --dependencies Install missing dependencies"
    echo
    echo "HOST GROUP MANAGEMENT:"
    echo "    msync --create-group NAME host1,host2,...  Create a host group"
    echo "    msync --list-groups                        List all host groups"
    echo "    msync --show-group NAME                    Show hosts in a group"
    echo "    msync --delete-group NAME                  Delete a host group"
    echo "    msync [OPTIONS] SOURCE DEST @groupname     Use a host group"
    echo
    echo "ENVIRONMENT VARIABLES:"
    echo "    MSYNC_DEFAULT_USER       Set default remote user"
    echo "    MSYNC_PARALLEL_DEFAULT   Set default parallel transfer count"
    echo "    MSYNC_SSH_PORT           Set default SSH port"
    echo "    MSYNC_DEBUG              Enable debug output (set to 1)"
    echo
    echo "EXAMPLES:"
    echo "    msync                                      # Interactive mode"
    echo "    msync -r /src/ /dest/ host1,host2          # Basic transfer"
    echo "    msync -P 5 /data/ /backup/ host1,host2     # 5 parallel transfers"
    echo "    msync -m /file.txt /new/dir/ host1,host2   # Create dest dir"
    echo "    msync -u admin /app/ /opt/ server1,server2 # Use non-root user"
    echo
    echo "VERSION: ${VERSION}"
}

# Function to display version
show_version() {
    echo "msync version ${VERSION}"
}

# Function to manage host groups
manage_hostgroups() {
    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR" 2>/dev/null || {
        echo "Error: Failed to create config directory $CONFIG_DIR"
        return 1
    }
    
    case "$1" in
        --create-group)
            if [ -z "$2" ] || [ -z "$3" ]; then
                echo "Error: Group name and hosts required"
                echo "Usage: msync --create-group NAME host1,host2,..."
                return 1
            fi
            
            group_name="$2"
            hosts="$3"
            
            # Validate group name
            case "$group_name" in
                @*|*,*|*:*|*/*)
                    echo "Error: Invalid group name. Cannot start with @ or contain ,:/\\"
                    return 1
                    ;;
            esac
            
            # Check if group already exists
            if [ -f "$HOSTGROUPS_FILE" ]; then
                while IFS=: read -r name _; do
                    if [ "$name" = "$group_name" ]; then
                        echo "Error: Group '$group_name' already exists"
                        echo "Use --delete-group first if you want to recreate it"
                        return 1
                    fi
                done < "$HOSTGROUPS_FILE"
            fi
            
            # Save group to file
            echo "$group_name:$hosts" >> "$HOSTGROUPS_FILE"
            echo "Host group '$group_name' created with hosts: $hosts"
            return 0
            ;;
            
        --list-groups)
            if [ ! -f "$HOSTGROUPS_FILE" ]; then
                echo "No host groups defined yet"
                return 0
            fi
            
            echo "Defined host groups:"
            while IFS=: read -r name hosts; do
                host_count=$(echo "$hosts" | tr ',' '\n' | wc -l)
                echo "  @$name ($host_count hosts)"
            done < "$HOSTGROUPS_FILE"
            return 0
            ;;
            
        --show-group)
            if [ -z "$2" ]; then
                echo "Error: Group name required"
                echo "Usage: msync --show-group NAME"
                return 1
            fi
            
            group_name="$2"
            if [ ! -f "$HOSTGROUPS_FILE" ]; then
                echo "Error: No host groups defined"
                return 1
            fi
            
            found=false
            while IFS=: read -r name hosts; do
                if [ "$name" = "$group_name" ]; then
                    echo "Hosts in group '$group_name':"
                    echo "$hosts" | tr ',' '\n' | sed 's/^/  /'
                    found=true
                    break
                fi
            done < "$HOSTGROUPS_FILE"
            
            if [ "$found" != "true" ]; then
                echo "Error: Group '$group_name' not found"
                return 1
            fi
            return 0
            ;;
            
        --delete-group)
            if [ -z "$2" ]; then
                echo "Error: Group name required"
                echo "Usage: msync --delete-group NAME"
                return 1
            fi
            
            group_name="$2"
            if [ ! -f "$HOSTGROUPS_FILE" ]; then
                echo "Error: No host groups defined"
                return 1
            fi
            
            # Create temp file
            temp_file=$(mktemp)
            deleted=false
            
            while IFS=: read -r name hosts; do
                if [ "$name" != "$group_name" ]; then
                    echo "$name:$hosts" >> "$temp_file"
                else
                    deleted=true
                fi
            done < "$HOSTGROUPS_FILE"
            
            if [ "$deleted" = "true" ]; then
                mv "$temp_file" "$HOSTGROUPS_FILE"
                echo "Host group '$group_name' deleted"
                return 0
            else
                rm -f "$temp_file"
                echo "Error: Group '$group_name' not found"
                return 1
            fi
            ;;
    esac
}

# Function to resolve host group to host list
resolve_hostgroup() {
    local group=$1
    local group_name=${group#@}
    
    if [ ! -f "$HOSTGROUPS_FILE" ]; then
        echo "Error: No host groups defined"
        return 1
    fi
    
    local found=false
    local result=""
    
    while IFS=: read -r name hosts; do
        if [ "$name" = "$group_name" ]; then
            result="$hosts"
            found=true
            break
        fi
    done < "$HOSTGROUPS_FILE"
    
    if [ "$found" = "true" ]; then
        echo "$result"
        return 0
    else
        echo "Error: Host group '$group_name' not found"
        return 1
    fi
}

# Function to create remote directory
create_remote_dir() {
    local host=$1
    local port=$2
    local user=$3
    local dir=$4
    
    ssh -p "$port" -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "$user@$host" "mkdir -p \"$dir\"" 2>/dev/null
    return $?
}

# Function to validate IP address format
validate_ip() {
    local ip=$1
    local IFS='.'
    # shellcheck disable=SC2086
    set -- ${ip}
    
    # Must have 4 parts
    if [ $# -ne 4 ]; then
        return 1
    fi
    
    # Each part must be a number between 0 and 255
    for octet; do
        # Check if it's a number
        case $octet in
            ''|*[!0-9]*) return 1 ;;
        esac
        
        # Check range
        if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
            return 1
        fi
    done
    
    return 0
}

# Function to test ssh connection
test_ssh_connection() {
    local host=$1
    local port=$2
    local user=$3
    
    [ -z "$port" ] && port=22
    
    ssh -p "$port" -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR "$user@$host" exit 2>/dev/null
    return $?
}

# Function for interactive mode
interactive_mode() {
    local dry_run=$1
    local force=$2
    local recursive=$3
    local port=$4
    local limit=$5
    local exclude=$6
    local parallel=$7
    local mkdir_opt=$8
    local remote_user=$9
    
    echo ":: Multi-Host Sync Tool (msync) ::"
    echo
    
    [ "$dry_run" = "true" ] && echo "! DRY RUN MODE: No changes will be made"
    
    # Ask for remote hosts
    while true; do
        echo -n "Enter hosts (comma-separated or @group): "
        read -r hosts_input
        
        if [ -z "$hosts_input" ]; then
            echo "Error: No hosts provided"
            continue
        fi
        
        # Check if it's a host group
        if [ "${hosts_input#@}" != "$hosts_input" ]; then
            local resolved_hosts
            if ! resolved_hosts=$(resolve_hostgroup "$hosts_input"); then
                echo "$resolved_hosts"  # Error message
                continue
            fi
            hosts_input="$resolved_hosts"
            echo "Group resolved to: $hosts_input"
        fi
        
        # Clean up input and convert to array
        # Replace comma-space with just comma
        hosts_input=$(echo "$hosts_input" | tr -s ' ' | sed 's/ *, */,/g')
        
        # Create array of hosts
        IFS=',' read -r -a hosts <<< "$hosts_input"
        
        invalid_hosts=""
        unreachable_hosts=""
        
        # Validate hosts
        for host in "${hosts[@]}"; do
            [ -z "$host" ] && continue
            
            # If it's an IP, validate it
            if [ "${host//[0-9.]/}" = "" ]; then
                if ! validate_ip "$host"; then
                    [ -n "$invalid_hosts" ] && invalid_hosts="$invalid_hosts,$host" || invalid_hosts="$host"
                fi
            fi
            
            # Test SSH connection if not in force mode
            if [ "$force" != "true" ]; then
                echo -n "Testing connection to ${host}... "
                if test_ssh_connection "$host" "$port" "$remote_user"; then
                    echo "OK"
                else
                    echo "Failed"
                    [ -n "$unreachable_hosts" ] && unreachable_hosts="$unreachable_hosts,$host" || unreachable_hosts="$host"
                fi
            fi
        done
        
        # Report validation issues
        if [ -n "$invalid_hosts" ]; then
            echo "Error: Invalid IP format: $invalid_hosts"
        fi
        
        if [ -n "$unreachable_hosts" ]; then
            echo "Warning: Can't reach: $unreachable_hosts"
            echo -n "Continue without these hosts? (y/n): "
            read -r continue_without
            if [ "$continue_without" != "y" ] && [ "$continue_without" != "Y" ]; then
                continue
            fi
            
            # Remove unreachable hosts
            local new_hosts=""
            IFS=',' read -r -a unreachable_array <<< "$unreachable_hosts"
            
            for host in "${hosts[@]}"; do
                local skip=false
                for unreachable in "${unreachable_array[@]}"; do
                    if [ "$host" = "$unreachable" ]; then
                        skip=true
                        break
                    fi
                done
                if [ "$skip" = "false" ]; then
                    [ -n "$new_hosts" ] && new_hosts="$new_hosts,$host" || new_hosts="$host"
                fi
            done
            
            # If no hosts remain, start over
            if [ -z "$new_hosts" ]; then
                echo "Error: No valid hosts remain."
                continue
            fi
            
            # Update hosts array
            hosts_input="$new_hosts"
            IFS=',' read -r -a hosts <<< "$hosts_input"
        fi
        
        break
    done

    # Ask for source path
    while true; do
        echo -n "Enter source path: "
        read -r source_path
        source_path="${source_path/#\~/$HOME}"
        [ ! -e "$source_path" ] && { echo "Error: Path '$source_path' not found"; continue; }
        break
    done

    # Ask for destination path
    while true; do
        echo -n "Enter destination path: "
        read -r dest_path
        [ -z "$dest_path" ] && { echo "Error: Destination cannot be empty"; continue; }
        break
    done

    # Build rsync options
    rsync_options="-az"
    
    # Add progress only in interactive mode
    rsync_options="$rsync_options --progress"
    [ "$dry_run" = "true" ] && rsync_options="$rsync_options --dry-run"
    [ "$recursive" = "true" ] && rsync_options="$rsync_options --recursive"
    [ -n "$limit" ] && rsync_options="$rsync_options --bwlimit=$limit"
    [ -n "$exclude" ] && rsync_options="$rsync_options --exclude=$exclude"

    # Show summary
    echo
    echo ":: Summary ::"
    echo "Source: $source_path"
    echo "Destination: $dest_path"
    echo "Remote user: $remote_user"
    echo "Hosts (${#hosts[@]}): ${hosts[*]}"
    echo "Options: $rsync_options"
    [ "$mkdir_opt" = "true" ] && echo "Will create destination directory if needed"
    [ "$parallel" -gt 1 ] && echo "Will run $parallel transfers in parallel"
    echo

    # Ask for confirmation
    echo -n "Proceed with sync? (y/n): "
    read -r confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Operation canceled"
        exit 0
    fi

    # Convert hosts array to comma-separated string for execute_sync
    hosts_string=$(IFS=,; echo "${hosts[*]}")
    
    # Perform the sync
    execute_sync "$source_path" "$dest_path" "$hosts_string" "$rsync_options" "false" "$port" "$parallel" "$mkdir_opt" "$remote_user"
}

# Function to execute the sync operation
execute_sync() {
    local source_path=$1
    local dest_path=$2
    local hosts_string=$3
    local rsync_options=$4
    local quiet_mode=$5
    local port=$6
    local parallel=$7
    local mkdir_opt=$8
    local remote_user=$9
    
    # Convert hosts string back to array
    IFS=',' read -r -a host_list <<< "$hosts_string"
    
    # Track results
    successful_hosts=""
    failed_hosts=""
    
    total_hosts=${#host_list[@]}
    
    # Create temp directory for parallel job tracking
    temp_dir=$(mktemp -d)
    if [ ! -d "$temp_dir" ]; then
        echo "Error: Failed to create temporary directory"
        return 1
    fi
    
    # Function to process a single host
    process_host() {
        local host=$1
        local host_num=$2
        local result_file="${temp_dir}/result_${host_num}"
        local log_file="${temp_dir}/log_${host_num}"
        
        # Show minimal progress
        if [ "$quiet_mode" != "true" ]; then
            echo "[$host_num/$total_hosts] ► Processing $host"
        fi
        
        # Create destination directory if needed
        if [ "$mkdir_opt" = "true" ]; then
            local dest_dir
            # If dest path ends with /, it's a directory
            # Otherwise, get the parent directory
            if [ "${dest_path%/}" != "$dest_path" ]; then
                dest_dir="$dest_path"
            else
                dest_dir=$(dirname "$dest_path")
            fi
            
            if [ "$quiet_mode" != "true" ]; then
                echo "Creating directory: $dest_dir"
            fi
            
            create_remote_dir "$host" "$port" "$remote_user" "$dest_dir"
        fi
        
        # Build the rsync command
        ssh_opts="-p $port"
        rsync_cmd="rsync $rsync_options -e 'ssh $ssh_opts' \"$source_path\" \"$remote_user@$host:$dest_path\""
        
        # Execute rsync
        if [ "$quiet_mode" = "true" ]; then
            eval "$rsync_cmd" >/dev/null 2>&1
            echo $? > "$result_file"
        else
            eval "$rsync_cmd" > "$log_file" 2>&1
            echo $? > "$result_file"
            cat "$log_file"
        fi
        
        # Signal completion
        touch "${temp_dir}/done_${host_num}"
    }
    
    # Launch processes in parallel but limit concurrency
    running=0
    next_host=0
    
    while [ $next_host -lt "$total_hosts" ] || [ $running -gt 0 ]; do
        # Start new jobs if under the limit and hosts remain
        while [ $running -lt "$parallel" ] && [ $next_host -lt "$total_hosts" ]; do
            host_num=$((next_host + 1))
            process_host "${host_list[$next_host]}" "$host_num" &
            
            # Store PID for monitoring
            pid=$!
            echo $pid > "${temp_dir}/pid_${host_num}"
            
            next_host=$((next_host + 1))
            running=$((running + 1))
            
            # Small delay to avoid SSH connection flood
            sleep 0.5
        done
        
        # Check for completed jobs
        for i in $(seq 1 "$total_hosts"); do
            if [ -f "${temp_dir}/done_${i}" ] && [ ! -f "${temp_dir}/processed_${i}" ]; then
                result=$(cat "${temp_dir}/result_${i}")
                host="${host_list[$((i-1))]}"
                
                if [ "$result" = "0" ]; then
                    if [ "$quiet_mode" != "true" ]; then
                        echo "✓ Sync to $host completed"
                    fi
                    [ -z "$successful_hosts" ] && successful_hosts="$host" || successful_hosts="$successful_hosts,$host"
                else
                    if [ "$quiet_mode" != "true" ]; then
                        echo "✗ Failed to sync to $host (code: $result)"
                    fi
                    [ -z "$failed_hosts" ] && failed_hosts="$host" || failed_hosts="$failed_hosts,$host"
                fi
                
                # Mark as processed
                touch "${temp_dir}/processed_${i}"
                running=$((running - 1))
            fi
        done
        
        # Avoid CPU spinning
        [ $running -ge "$parallel" ] && sleep 1
    done
    
    # Clean up temp directory
    rm -rf "$temp_dir"
    
    # Print final summary if not quiet
    if [ "$quiet_mode" != "true" ]; then
        echo
        echo ":: Transfer Results ::"
        
        # Count successful hosts
        local success_count=0
        if [ -n "$successful_hosts" ]; then
            IFS=',' read -r -a success_array <<< "$successful_hosts"
            success_count=${#success_array[@]}
        fi
        
        # Count failed hosts
        local failed_count=0
        if [ -n "$failed_hosts" ]; then
            IFS=',' read -r -a failed_array <<< "$failed_hosts"
            failed_count=${#failed_array[@]}
        fi
        
        echo "Total: $total_hosts | Success: $success_count | Failed: $failed_count"
        
        if [ -n "$failed_hosts" ]; then
            echo "Failed hosts: $failed_hosts"
        fi
    fi
    
    # Exit with appropriate code
    if [ -n "$failed_hosts" ]; then
        return 1
    else
        return 0
    fi
}

# Main script execution
main() {
    # Default values
    interactive=false
    dry_run=false
    force=false
    quiet=false
    recursive=false
    port="$DEFAULT_SSH_PORT"
    limit=""
    exclude=""
    parallel="$DEFAULT_PARALLEL"
    mkdir_opt=false
    remote_user="$DEFAULT_USER"
    
    # Check for hostgroup management commands
    case "$1" in
        --create-group|--list-groups|--show-group|--delete-group)
            manage_hostgroups "$@"
            exit $?
            ;;
    esac
    
    # Check for dependency installation
    case "$1" in
        -d|--dependencies)
            install_dependencies
            exit $?
            ;;
    esac
    
    # If no arguments, default to interactive
    [ $# -eq 0 ] && interactive=true
    
    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) show_help; exit 0 ;;
            -v|--version) show_version; exit 0 ;;
            -i|--interactive) interactive=true; shift ;;
            -n|--dry-run) dry_run=true; shift ;;
            -f|--force) force=true; shift ;;
            -q|--quiet) quiet=true; shift ;;
            -r|--recursive) recursive=true; shift ;;
            -p|--port) port="$2"; shift 2 ;;
            -l|--limit) limit="$2"; shift 2 ;;
            -e|--exclude) exclude="$2"; shift 2 ;;
            -P|--parallel) parallel="$2"; shift 2 ;;
            -m|--mkdir) mkdir_opt=true; shift ;;
            -u|--user) remote_user="$2"; shift 2 ;;
            -d|--dependencies) 
                install_dependencies
                exit $?
                ;;
            *) break ;;
        esac
    done
    
    # Check for required dependencies
    if ! check_dependencies; then
        exit 3
    fi
    
    # Validate parallel count
    case "$parallel" in
        ''|*[!0-9]*)
            echo "Error: Parallel count must be a positive integer"
            exit 2
            ;;
        *)
            if [ "$parallel" -lt 1 ]; then
                echo "Error: Parallel count must be at least 1"
                exit 2
            fi
            ;;
    esac
    
    # Set rsync options
    rsync_options="-az"
    [ "$dry_run" = "true" ] && rsync_options="$rsync_options --dry-run"
    [ "$recursive" = "true" ] && rsync_options="$rsync_options --recursive"
    [ -n "$limit" ] && rsync_options="$rsync_options --bwlimit=$limit"
    [ -n "$exclude" ] && rsync_options="$rsync_options --exclude=$exclude"
    
    # Handle interactive mode
    if [ "$interactive" = "true" ]; then
        interactive_mode "$dry_run" "$force" "$recursive" "$port" "$limit" "$exclude" "$parallel" "$mkdir_opt" "$remote_user"
        exit $?
    fi
    
    # Non-interactive requires 3 arguments
    if [ $# -ne 3 ]; then
        echo "Error: Command-line mode requires SOURCE, DESTINATION, and HOSTS"
        echo "Run 'msync --help' for usage"
        exit 2
    fi
    
    source_path="$1"
    dest_path="$2"
    host_param="$3"
    
    # Check if using a host group
    if [ "${host_param#@}" != "$host_param" ]; then
        local host_string
        if ! host_string=$(resolve_hostgroup "$host_param"); then
            echo "$host_string"  # Error message from resolve_hostgroup
            exit 2
        fi
        host_param="$host_string"
    fi
    
    # Validate source
    if [ ! -e "$source_path" ]; then
        echo "Error: Source '$source_path' not found"
        exit 2
    fi
    
    # Validate destination
    if [ -z "$dest_path" ]; then
        echo "Error: Destination cannot be empty"
        exit 2
    fi
    
    # Clean up host string - replace comma-space with just comma
    host_param=$(echo "$host_param" | tr -s ' ' | sed 's/ *, */,/g')
    
    # Minimal output in non-quiet mode
    if [ "$quiet" != "true" ]; then
        echo "Syncing '${source_path}' → '${dest_path}' on: ${host_param//,/, }"
        [ "$parallel" -gt 1 ] && echo "Running $parallel transfers in parallel"
        echo "Using remote user: $remote_user"
    fi
    
    execute_sync "$source_path" "$dest_path" "$host_param" "$rsync_options" "$quiet" "$port" "$parallel" "$mkdir_opt" "$remote_user"
    exit_code=$?
    
    exit $exit_code
}

# Execute main
main "$@"
