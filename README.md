# msync - Multi-Host File Synchronization Tool

![Version](https://img.shields.io/badge/version-1.5.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

`msync` is a powerful command-line utility that extends rsync functionality to easily synchronize files or directories to multiple hosts simultaneously. It provides both an interactive mode for ease of use and a command-line interface for scripting and automation.

## Features

- **Multi-Host Transfers**: Sync to multiple hosts in one command
- **Parallel Execution**: Execute transfers in parallel for better performance
- **Host Groups**: Define and manage reusable groups of hosts
- **Remote Directory Creation**: Automatically create destination directories
- **Bandwidth Control**: Limit transfer speed as needed
- **Flexible Configuration**: Support for various rsync options
- **Interactive Mode**: User-friendly interactive interface
- **Command-Line Mode**: Scriptable for automation
- **Error Handling**: Comprehensive error reporting and tracking

## Installation

### Prerequisites

- Linux/Unix-based system
- Bash shell
- rsync installed
- SSH access to target hosts (preferably with key-based authentication)

### Quick Install

```bash
# Clone the repository
git clone https://github.com/yourusername/msync.git

# Make the script executable
chmod +x msync/msync

# Move to a directory in your PATH
sudo cp msync/msync /usr/local/bin/

# Verify installation
msync --version
```

## Usage

### Basic Syntax

```
msync [OPTIONS] [SOURCE] [DESTINATION] [HOSTS]
```

### Example Commands

```bash
# Interactive mode
msync

# Synchronize a file to multiple hosts
msync /etc/config.conf /etc/ server1,server2,server3

# Recursively copy a directory with 5 parallel transfers
msync -r -P 5 /var/www/ /var/www/ web1,web2,web3,web4,web5

# Create destination directory if it doesn't exist
msync -m /backup/file.tar.gz /new/path/ backup1,backup2

# Use bandwidth limiting (1MB/s) and dry run
msync -n -l 1m /data/ /backup/ db1,db2

# Use a defined host group
msync /scripts/update.sh /scripts/ @webservers
```

### Host Groups

```bash
# Create a host group
msync --create-group webservers web1,web2,web3,web4

# List all defined host groups
msync --list-groups

# Show hosts in a specific group
msync --show-group webservers

# Delete a host group
msync --delete-group webservers
```

## Command-Line Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Display help information |
| `-v, --version` | Show version information |
| `-i, --interactive` | Force interactive mode |
| `-q, --quiet` | Minimal output (for scripting) |
| `-n, --dry-run` | Test run without making changes |
| `-f, --force` | Skip connection tests |
| `-r, --recursive` | Recursive directory copy |
| `-p, --port PORT` | Custom SSH port |
| `-l, --limit RATE` | Bandwidth limiting (e.g., 1000k, 5m) |
| `-e, --exclude PAT` | Exclude files matching pattern |
| `-P, --parallel N` | Run N transfers in parallel (default: 3) |
| `-m, --mkdir` | Create destination directory if missing |

## Host Group Management

| Command | Description |
|--------|-------------|
| `--create-group NAME HOSTS` | Create a new host group |
| `--list-groups` | List all defined host groups |
| `--show-group NAME` | Show hosts in a specific group |
| `--delete-group NAME` | Delete a host group |

## Configuration

Host groups are stored in `~/.config/msync/hostgroups`. This is a simple text file with entries in the format:

```
groupname:host1,host2,host3
```

## Interactive Mode

When run without arguments, `msync` operates in interactive mode, guiding you through the process:

1. Enter target hosts (comma-separated or @group)
2. Enter source path
3. Enter destination path
4. Confirm the operation details
5. Monitor the transfer progress
6. View summary of results

## Exit Codes

- `0`: All transfers successful
- `1`: One or more transfers failed

## Examples in Action

### Synchronize a configuration file to multiple servers

```bash
msync /etc/nginx/nginx.conf /etc/nginx/ web1,web2,web3
```

### Deploy an application to all production servers with a host group

```bash
# Create the host group (one-time setup)
msync --create-group prod-web web1,web2,web3,web4

# Deploy the application
msync -r /var/www/app/ /var/www/ @prod-web
```

### Backup data from all database servers in parallel

```bash
msync -P 4 -m /data/db_backup.sql /backups/$(date +%F)/ db1,db2,db3,db4
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Inspired by the need to simplify multi-host file synchronization
- Built on the powerful rsync utility
- Special thanks to the open-source community for feedback and inspiration

---

*Note: msync requires root access on remote hosts in the current implementation. Make sure you have appropriate permissions.*
