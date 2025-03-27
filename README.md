# msync - Multi-Host File Synchronization Tool

![Version](https://img.shields.io/badge/version-1.5.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Compatibility](https://img.shields.io/badge/shell-bash%20%7C%20zsh%20%7C%20sh-orange.svg)

`msync` is a powerful command-line utility that extends rsync functionality to easily synchronize files or directories to multiple hosts simultaneously. It provides both an interactive mode for ease of use and a command-line interface for scripting and automation.

## Features

- **Multi-Host Transfers**: Sync to multiple hosts in one command
- **Parallel Execution**: Execute transfers in parallel for better performance
- **Host Groups**: Define and manage reusable groups of hosts
- **Remote Directory Creation**: Automatically create destination directories
- **Bandwidth Control**: Limit transfer speed as needed
- **Shell Compatibility**: Works across bash, zsh, and POSIX shells
- **Auto-Dependency Management**: Detects and installs required dependencies
- **User Configuration**: Customize defaults via environment variables
- **Non-Root Transfers**: Support for any remote user account
- **Debug Mode**: Built-in troubleshooting capabilities

## Installation

### Prerequisites

- Linux/Unix-based system (including macOS)
- Bash, Zsh, or POSIX-compatible shell
- rsync and SSH (will be auto-installed if missing)

### Quick Install

```bash
# Clone the repository
git clone https://github.com/Harsh-2002/msync.git

# Make the script executable
chmod +x msync/msync

# Move to a directory in your PATH
sudo cp msync/msync /usr/local/bin/

# Verify installation
msync --version
```

### One-Line Install

```bash
sudo curl -sL https://raw.githubusercontent.com/Harsh-2002/msync/main/msync.sh -o /usr/local/bin/msync && sudo chmod +x /usr/local/bin/msync && sudo msync --help

```

### Install Dependencies (if needed)

```bash
msync --dependencies
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

# Use a specific remote user
msync -u deploy /app/release.zip /opt/apps/ app1,app2,app3
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
| `-u, --user USER` | Remote username (default: root) |
| `-d, --dependencies` | Install missing dependencies |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `MSYNC_DEFAULT_USER` | Default remote user for transfers (default: root) |
| `MSYNC_PARALLEL_DEFAULT` | Default number of parallel transfers (default: 3) |
| `MSYNC_SSH_PORT` | Default SSH port (default: 22) |
| `MSYNC_DEBUG` | Enable debug output when set to 1 |

## Host Group Management

Host groups are stored in `~/.config/msync/hostgroups`. This is a simple text file with entries in the format:

```
groupname:host1,host2,host3
```

| Command | Description |
|--------|-------------|
| `--create-group NAME HOSTS` | Create a new host group |
| `--list-groups` | List all defined host groups |
| `--show-group NAME` | Show hosts in a specific group |
| `--delete-group NAME` | Delete a host group |

## Shell Compatibility

`msync` is designed to work across different shells:

- **Bash**: Full compatibility with all features
- **Zsh**: Full compatibility with all features
- **POSIX shells** (sh, dash, etc.): Compatible with all core features

The script automatically detects the shell environment and adjusts its behavior accordingly.

## Dependency Management

`msync` will check for required dependencies (rsync, ssh) and can attempt to install them automatically:

```bash
# Automatically check and install missing dependencies
msync --dependencies
```

Supported package managers:
- apt (Debian, Ubuntu)
- yum/dnf (RHEL, CentOS, Fedora)
- apk (Alpine)
- brew (macOS)
- pacman (Arch Linux)
- zypper (openSUSE)

## Interactive Mode

When run without arguments, `msync` operates in interactive mode, guiding you through the process step-by-step:

1. Enter target hosts (comma-separated or @group)
2. Enter source path
3. Enter destination path
4. Confirm the operation details
5. Monitor the transfer progress
6. View summary of results

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | All transfers successful |
| `1` | One or more transfers failed |
| `2` | Invalid arguments or configuration |
| `3` | Missing dependencies |

## Examples in Action

### Basic File Transfer

```bash
# Transfer a configuration file to multiple servers
msync /etc/nginx/nginx.conf /etc/nginx/ web1,web2,web3
```

### Application Deployment Using Host Groups

```bash
# Create the host group (one-time setup)
msync --create-group prod-web web1,web2,web3,web4

# Deploy the application with a non-root user
msync -r -u deploy /var/www/app/ /var/www/ @prod-web
```

### Backup Operations

```bash
# Backup data from all database servers in parallel
msync -P 4 -m /data/db_backup.sql /backups/$(date +%F)/ db1,db2,db3,db4
```

### Scripting Example

```bash
#!/bin/bash
# Example backup script

# Set variables
DATE=$(date +%Y-%m-%d)
BACKUP_DIR="/tmp/backups/$DATE"
BACKUP_SERVERS="backup1,backup2"
LOG_FILE="/var/log/backup-$DATE.log"

# Create local backup directory
mkdir -p "$BACKUP_DIR"

# Backup database
mysqldump -u root mydatabase > "$BACKUP_DIR/database.sql"

# Sync to backup servers with minimal output
if msync -q -m "$BACKUP_DIR/" /remote/backups/ "$BACKUP_SERVERS"; then
  echo "Backup completed successfully" >> "$LOG_FILE"
else
  echo "Backup failed to one or more servers" >> "$LOG_FILE"
fi
```

## Troubleshooting

### Common Issues

1. **Permission denied**: Ensure you have SSH access to the remote hosts with the specified user
2. **rsync not found**: Run `msync --dependencies` to install necessary dependencies
3. **Host unreachable**: Check network connectivity and hostname resolution
4. **SSH authentication failures**: Verify SSH key setup or credentials

### Debug Mode

For more detailed debug output:

```bash
MSYNC_DEBUG=1 msync [options]
```

## Security Considerations

- By default, msync uses the root user on remote hosts. Use the `-u` option to specify a different user when possible.
- Ensure SSH key-based authentication is properly set up for automated operation.
- Consider using SSH config to manage complex connection requirements.

## Advanced Configuration

For users with complex requirements, consider creating shell aliases:

```bash
# Add to ~/.bashrc or ~/.zshrc
alias msync-web='msync -u webadmin -P 5 -r'
alias msync-backup='msync -u backupuser -l 5m -m'
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -am 'Add some amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Inspired by the need to simplify multi-host file synchronization
- Built on the powerful rsync utility
- Special thanks to the open-source community for feedback and inspiration

---

*Note: This documentation assumes the script is installed as `msync`. If you install it under a different name, adjust commands accordingly.*
