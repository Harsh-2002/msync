#!/bin/bash

# Script version
VERSION="1.5.0"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/msync"
HOSTGROUPS_FILE="$CONFIG_DIR/hostgroups"

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
    echo "    -p, --port PORT    Custom SSH port"
    echo "    -l, --limit RATE   Limit bandwidth (e.g., 1000k)"
    echo "    -e, --exclude PAT  Exclude files matching pattern"
    echo "    -P, --parallel N   Run N transfers in parallel (default: 3)"
    echo "    -m, --mkdir        Create destination directory if missing"
    echo
    echo "HOST GROUP MANAGEMENT:"
    echo "    msync --create-group NAME host1,host2,...  Create a host group"
    echo "    msync --list-groups                        List all host groups"
    echo "    msync --show-group NAME                    Show hosts in a group"
    echo "    msync --delete-group NAME                  Delete a host group"
    echo "    msync [OPTIONS] SOURCE DEST @groupname     Use a host group"
    echo
    echo "EXAMPLES:"
    echo "    msync                                      # Interactive mode"
    echo "    msync -r /src/ /dest/ host1,host2          # Basic transfer"
    echo "    msync -P 5 /data/ /backup/ host1,host2     # 5 parallel transfers"
    echo "    msync -m /file.txt /new/dir/ host1,host2   # Create dest dir"
    echo "    msync --create-group webservers web1,web2,web3"
    echo "    msync /config.conf /etc/ @webservers       # Use host group"
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
    mkdir -p "$CONFIG_DIR" 2>/dev/null
    
    case "$1" in
        --create-group)
            if [[ -z "$2" || -z "$3" ]]; then
                echo "Error: Group name and hosts required"
                echo "Usage: msync --create-group NAME host1,host2,..."
                exit 1
            fi
            
            group_name="$2"
            hosts="$3"
            
            # Validate group name
            if [[ "$group_name" == @* || "$group_name" =~ [,:/\\] ]]; then
                echo "Error: Invalid group name. Cannot start with @ or contain ,:/\\"
                exit 1
            fi
            
            # Save group to file
            echo "$group_name:$hosts" >> "$HOSTGROUPS_FILE"
            echo "Host group '$group_name' created with hosts: $hosts"
            exit 0
            ;;
            
        --list-groups)
            if [[ ! -f "$HOSTGROUPS_FILE" ]]; then
                echo "No host groups defined yet"
                exit 0
            fi
            
            echo "Defined host groups:"
            while IFS=: read -r name hosts; do
                host_count=$(echo "$hosts" | tr ',' '\n' | wc -l)
                echo "  @$name ($host_count hosts)"
            done < "$HOSTGROUPS_FILE"
            exit 0
            ;;
            
        --show-group)
            if [[ -z "$2" ]]; then
                echo "Error: Group name required"
                echo "Usage: msync --show-group NAME"
                exit 1
            fi
            
            group_name="$2"
            if [[ ! -f "$HOSTGROUPS_FILE" ]]; then
                echo "Error: No host groups defined"
                exit 1
            fi
            
            found=false
            while IFS=: read -r name hosts; do
                if [[ "$name" == "$group_name" ]]; then
                    echo "Hosts in group '$group_name':"
                    echo "$hosts" | tr ',' '\n' | sed 's/^/  /'
                    found=true
                    break
                fi
            done < "$HOSTGROUPS_FILE"
            
            if [[ "$found" != "true" ]]; then
                echo "Error: Group '$group_name' not found"
                exit 1
            fi
            exit 0
            ;;
            
        --delete-group)
            if [[ -z "$2" ]]; then
                echo "Error: Group name required"
                echo "Usage: msync --delete-group NAME"
                exit 1
            fi
            
            group_name="$2"
            if [[ ! -f "$HOSTGROUPS_FILE" ]]; then
                echo "Error: No host groups defined"
                exit 1
            fi
            
            # Create temp file
            temp_file=$(mktemp)
            deleted=false
            
            while IFS=: read -r name hosts; do
                if [[ "$name" != "$group_name" ]]; then
                    echo "$name:$hosts" >> "$temp_file"
                else
                    deleted=true
                fi
            done < "$HOSTGROUPS_FILE"
            
            if [[ "$deleted" == "true" ]]; then
                mv "$temp_file" "$HOSTGROUPS_FILE"
                echo "Host group '$group_name' deleted"
                exit 0
            else
                rm "$temp_file"
                echo "Error: Group '$group_name' not found"
                exit 1
            fi
            ;;
    esac
}

# Function to resolve host group to host list
resolve_hostgroup() {
    local group=$1
    local group_name=${group#@}
    
    if [[ ! -f "$HOSTGROUPS_FILE" ]]; then
        echo "Error: No host groups defined"
        return 1
    fi
    
    local found=false
    local result=""
    
    while IFS=: read -r name hosts; do
        if [[ "$name" == "$group_name" ]]; then
            result="$hosts"
            found=true
            break
        fi
    done < "$HOSTGROUPS_FILE"
    
    if [[ "$found" == "true" ]]; then
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
    local dir=$3
    
    ssh -p "$port" -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "root@$host" "mkdir -p \"$dir\"" 2>/dev/null
    return $?
}

# Function to validate IP address format
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a ip_segments <<< "$ip"
        for segment in "${ip_segments[@]}"; do
            if [[ $segment -lt 0 || $segment -gt 255 ]]; then
                return 1 # Invalid IP
            fi
        done
        return 0 # Valid IP
    else
        return 1 # Invalid format
    fi
}

# Function to test ssh connection
test_ssh_connection() {
    local host=$1
    local port=$2
    [[ -z "$port" ]] && port=22
    
    ssh -p "$port" -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR "root@$host" exit 2>/dev/null
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
    
    echo ":: Multi-Host Sync Tool (msync) ::"
    echo
    
    [[ "$dry_run" == "true" ]] && echo "! DRY RUN MODE: No changes will be made"
    
    # Ask for remote hosts
    while true; do
        echo -n "Enter hosts (comma-separated or @group): "
        read -r hosts_input
        
        if [[ -z "$hosts_input" ]]; then
            echo "Error: No hosts provided"
            continue
        fi
        
        # Check if it's a host group
        if [[ "$hosts_input" == @* ]]; then
            local resolved_hosts
            if ! resolved_hosts=$(resolve_hostgroup "$hosts_input"); then
                echo "$resolved_hosts"  # Error message
                continue
            fi
            hosts_input="$resolved_hosts"
            echo "Group resolved to: $hosts_input"
        fi
        
        # Clean up input and convert to array
        hosts_input=${hosts_input// *,*/,}
        IFS=',' read -ra hosts <<< "$hosts_input"
        invalid_hosts=()
        unreachable_hosts=()
        
        # Validate hosts
        for host in "${hosts[@]}"; do
            [[ -z "$host" ]] && continue
            
            if [[ $host =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && ! validate_ip "$host"; then
                invalid_hosts+=("$host")
            fi
            
            if [[ "$force" != "true" ]]; then
                echo -n "Testing connection to ${host}... "
                if test_ssh_connection "$host" "$port"; then
                    echo "OK"
                else
                    echo "Failed"
                    unreachable_hosts+=("$host")
                fi
            fi
        done
        
        # Report validation issues
        if [[ ${#invalid_hosts[@]} -gt 0 ]]; then
            echo "Error: Invalid IP format: ${invalid_hosts[*]}"
        fi
        
        if [[ ${#unreachable_hosts[@]} -gt 0 ]]; then
            echo "Warning: Can't reach: ${unreachable_hosts[*]}"
            echo -n "Continue without these hosts? (y/n): "
            read -r continue_without
            if [[ "$continue_without" != "y" && "$continue_without" != "Y" ]]; then
                continue
            fi
            
            # Remove unreachable hosts
            for unreachable in "${unreachable_hosts[@]}"; do
                for i in "${!hosts[@]}"; do
                    [[ "${hosts[i]}" = "$unreachable" ]] && unset 'hosts[i]'
                done
            done
            hosts=("${hosts[@]}")
        fi
        
        [[ ${#hosts[@]} -eq 0 ]] && { echo "Error: No valid hosts remain."; continue; }
        break
    done

    # Ask for source path
    while true; do
        echo -n "Enter source path: "
        read -r source_path
        source_path="${source_path/#\~/$HOME}"
        [[ ! -e "$source_path" ]] && { echo "Error: Path '$source_path' not found"; continue; }
        break
    done

    # Ask for destination path
    while true; do
        echo -n "Enter destination path: "
        read -r dest_path
        [[ -z "$dest_path" ]] && { echo "Error: Destination cannot be empty"; continue; }
        break
    done

    # Build rsync options
    rsync_options="-az"
    # Add progress only in interactive mode
    rsync_options="$rsync_options --progress"
    [[ "$dry_run" == "true" ]] && rsync_options="$rsync_options --dry-run"
    [[ "$recursive" == "true" ]] && rsync_options="$rsync_options --recursive"
    [[ -n "$limit" ]] && rsync_options="$rsync_options --bwlimit=$limit"
    [[ -n "$exclude" ]] && rsync_options="$rsync_options --exclude=$exclude"

    # Show summary
    echo
    echo ":: Summary ::"
    echo "Source: $source_path"
    echo "Destination: $dest_path"
    echo "Hosts (${#hosts[@]}): ${hosts[*]}"
    echo "Options: $rsync_options"
    [[ "$mkdir_opt" == "true" ]] && echo "Will create destination directory if needed"
    [[ "$parallel" -gt 1 ]] && echo "Will run $parallel transfers in parallel"
    echo

    # Ask for confirmation
    echo -n "Proceed with sync? (y/n): "
    read -r confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "Operation canceled"; exit 0; }

    # Convert hosts array to comma-separated string for execute_sync
    local hosts_string
    hosts_string=$(IFS=,; echo "${hosts[*]}")
    
    # Perform the sync
    execute_sync "$source_path" "$dest_path" "$hosts_string" "$rsync_options" "false" "$port" "$parallel" "$mkdir_opt"
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
    
    # Convert hosts string back to array
    IFS=',' read -ra host_list <<< "$hosts_string"
    
    # Track results
    successful_hosts=()
    failed_hosts=()
    
    total_hosts=${#host_list[@]}
    
    # Create temp directory for parallel job tracking
    temp_dir=$(mktemp -d)
    
    # Function to process a single host
    process_host() {
        local host=$1
        local host_num=$2
        local result_file="${temp_dir}/result_${host_num}"
        local log_file="${temp_dir}/log_${host_num}"
        
        # Show minimal progress
        if [[ "$quiet_mode" != "true" ]]; then
            echo "[$host_num/$total_hosts] ► Processing $host"
        fi
        
        # Create destination directory if needed
        if [[ "$mkdir_opt" == "true" ]]; then
            local dest_dir
            # If dest path ends with /, it's a directory
            # Otherwise, get the parent directory
            if [[ "$dest_path" == */ ]]; then
                dest_dir="$dest_path"
            else
                dest_dir=$(dirname "$dest_path")
            fi
            
            if [[ "$quiet_mode" != "true" ]]; then
                echo "Creating directory: $dest_dir"
            fi
            
            create_remote_dir "$host" "$port" "$dest_dir"
        fi
        
        # Build the rsync command
        ssh_opts="-p $port"
        rsync_cmd="rsync $rsync_options -e 'ssh $ssh_opts' \"$source_path\" \"root@$host:$dest_path\""
        
        # Execute rsync
        if [[ "$quiet_mode" == "true" ]]; then
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
    
    while [[ $next_host -lt $total_hosts || $running -gt 0 ]]; do
        # Start new jobs if under the limit and hosts remain
        while [[ $running -lt $parallel && $next_host -lt $total_hosts ]]; do
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
        for ((i=1; i<=total_hosts; i++)); do
            if [[ -f "${temp_dir}/done_${i}" && ! -f "${temp_dir}/processed_${i}" ]]; then
                result=$(cat "${temp_dir}/result_${i}")
                host="${host_list[$((i-1))]}"
                
                if [[ $result -eq 0 ]]; then
                    if [[ "$quiet_mode" != "true" ]]; then
                        echo "✓ Sync to $host completed"
                    fi
                    successful_hosts+=("$host")
                else
                    if [[ "$quiet_mode" != "true" ]]; then
                        echo "✗ Failed to sync to $host (code: $result)"
                    fi
                    failed_hosts+=("$host")
                fi
                
                # Mark as processed
                touch "${temp_dir}/processed_${i}"
                running=$((running - 1))
            fi
        done
        
        # Avoid CPU spinning
        [[ $running -ge $parallel ]] && sleep 1
    done
    
    # Clean up temp directory
    rm -rf "$temp_dir"
    
    # Print final summary if not quiet
    if [[ "$quiet_mode" != "true" ]]; then
        echo
        echo ":: Transfer Results ::"
        echo "Total: $total_hosts | Success: ${#successful_hosts[@]} | Failed: ${#failed_hosts[@]}"
        
        if [[ ${#failed_hosts[@]} -gt 0 ]]; then
            echo "Failed hosts: ${failed_hosts[*]}"
        fi
    fi
    
    # Exit with appropriate code
    [[ ${#failed_hosts[@]} -gt 0 ]] && exit 1 || exit 0
}

# Main script execution
main() {
    # Default values
    interactive=false
    dry_run=false
    force=false
    quiet=false
    recursive=false
    port="22"
    limit=""
    exclude=""
    parallel=3
    mkdir_opt=false
    
    # Check for hostgroup management commands
    case "$1" in
        --create-group|--list-groups|--show-group|--delete-group)
            manage_hostgroups "$@"
            ;;
    esac
    
    # If no arguments, default to interactive
    [[ $# -eq 0 ]] && interactive=true
    
    # Parse options
    while [[ $# -gt 0 ]]; do
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
            *) break ;;
        esac
    done
    
    # Validate parallel count
    if ! [[ "$parallel" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: Parallel count must be a positive integer"
        exit 1
    fi
    
    # Set rsync options
    rsync_options="-az"
    [[ "$dry_run" == "true" ]] && rsync_options="$rsync_options --dry-run"
    [[ "$recursive" == "true" ]] && rsync_options="$rsync_options --recursive"
    [[ -n "$limit" ]] && rsync_options="$rsync_options --bwlimit=$limit"
    [[ -n "$exclude" ]] && rsync_options="$rsync_options --exclude=$exclude"
    
    # Handle interactive mode
    if [[ "$interactive" == "true" ]]; then
        interactive_mode "$dry_run" "$force" "$recursive" "$port" "$limit" "$exclude" "$parallel" "$mkdir_opt"
        exit $?
    fi
    
    # Non-interactive requires 3 arguments
    if [[ $# -ne 3 ]]; then
        echo "Error: Command-line mode requires SOURCE, DESTINATION, and HOSTS"
        echo "Run 'msync --help' for usage"
        exit 1
    fi
    
    source_path="$1"
    dest_path="$2"
    host_param="$3"
    
    # Check if using a host group
    if [[ "$host_param" == @* ]]; then
        local host_string
        if ! host_string=$(resolve_hostgroup "$host_param"); then
            echo "$host_string"  # Error message from resolve_hostgroup
            exit 1
        fi
        host_param="$host_string"
    fi
    
    # Validate source
    if [[ ! -e "$source_path" ]]; then
        echo "Error: Source '$source_path' not found"
        exit 1
    fi
    
    # Validate destination
    if [[ -z "$dest_path" ]]; then
        echo "Error: Destination cannot be empty"
        exit 1
    fi
    
    # Clean up host string - replace comma-space with just comma
    host_param=${host_param// *,*/,}
    
    # Minimal output in non-quiet mode
    if [[ "$quiet" != "true" ]]; then
        echo "Syncing '${source_path}' → '${dest_path}' on: ${host_param//,/, }"
        [[ "$parallel" -gt 1 ]] && echo "Running $parallel transfers in parallel"
    fi
    
    execute_sync "$source_path" "$dest_path" "$host_param" "$rsync_options" "$quiet" "$port" "$parallel" "$mkdir_opt"
}

# Execute main
main "$@"
