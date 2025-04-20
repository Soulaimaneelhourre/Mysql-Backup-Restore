#!/bin/bash

# MySQL Backup Transfer and Restore Script
# Version: 2.0.0
# Description: Automates MySQL backup transfer between servers with robust error handling
# License: MIT
# Author: Your Name
# GitHub: https://github.com/yourusername/mysql-backup-restore

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_SOURCE_USER="user"
DEFAULT_SOURCE_IP="source_vm_ip"
DEFAULT_SOURCE_DIR="/path/to/backups"
DEFAULT_TARGET_USER="user"
DEFAULT_TARGET_IP="target_vm_ip"
DEFAULT_TARGET_DIR="/tmp"
DEFAULT_MYSQL_USER="mysql_user"
DEFAULT_MYSQL_PASS="mysql_password"
DEFAULT_NEW_DB_NAME="new_database_$(date +%Y%m%d_%H%M%S)"
DEFAULT_ENV_FILE="/path/to/.env"
DEFAULT_DB_NAME_VAR="DATABASE_STD"
DEFAULT_MAX_RETRIES=3
DEFAULT_RETRY_DELAY=10

# Global variables
LOG_FILE="mysql_restore_$(date +%Y%m%d_%H%M%S).log"
SESSION_NAME="mysql_restore_$(date +%Y%m%d)"
CONFIG_FILE="$(dirname "$0")/config"
VERSION="2.0.0"

# Function to display usage
usage() {
    echo -e "${BLUE}MySQL Backup Transfer and Restore Script v$VERSION${NC}"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --source-user USER       Source VM SSH username (default: $DEFAULT_SOURCE_USER)"
    echo "  --source-ip IP           Source VM IP address (default: $DEFAULT_SOURCE_IP)"
    echo "  --source-dir DIR         Source directory containing backups (default: $DEFAULT_SOURCE_DIR)"
    echo "  --target-user USER       Target VM SSH username (default: $DEFAULT_TARGET_USER)"
    echo "  --target-ip IP           Target VM IP address (default: $DEFAULT_TARGET_IP)"
    echo "  --target-dir DIR         Target directory for transfer (default: $DEFAULT_TARGET_DIR)"
    echo "  --mysql-user USER        MySQL username (default: $DEFAULT_MYSQL_USER)"
    echo "  --mysql-pass PASS        MySQL password (default: $DEFAULT_MYSQL_PASS)"
    echo "  --new-db-name NAME       New database name (default: $DEFAULT_NEW_DB_NAME)"
    echo "  --env-file FILE          Path to .env file (default: $DEFAULT_ENV_FILE)"
    echo "  --db-var VAR             Database variable name in .env (default: $DEFAULT_DB_NAME_VAR)"
    echo "  --max-retries NUM        Maximum retry attempts (default: $DEFAULT_MAX_RETRIES)"
    echo "  --retry-delay SECONDS    Delay between retries in seconds (default: $DEFAULT_RETRY_DELAY)"
    echo "  --config FILE            Load configuration from file"
    echo "  --detach                 Run in detached tmux session"
    echo "  --version                Show version information"
    echo "  --help                   Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --source-user admin --source-ip 192.168.1.100 --source-dir /backups/mysql \\"
    echo "     --target-user deploy --target-ip 192.168.1.200 --mysql-user root \\"
    echo "     --mysql-pass secret --new-db-name production_db --detach"
    echo
    echo "  $0 --config /path/to/config"
    exit 0
}

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
    exit 1
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to load configuration from file
load_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
    fi
    
    log_info "Loading configuration from: $config_file"
    
    # Source the config file
    # shellcheck disable=SC1090
    source "$config_file" || log_error "Failed to load configuration file"
}

# Function to find the latest backup file
find_latest_backup() {
    local backup_dir="$1"
    local ssh_output
    
    log_info "Searching for backup files in: $backup_dir"
    
    ssh_output=$(ssh -o ConnectTimeout=30 -o ConnectionAttempts=3 "${SOURCE_USER}@${SOURCE_IP}" \
        "find \"$backup_dir\" -type f \( -name '*.sql.gz' -o -name '*.sql' \) -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d' ' 2>/dev/null")
    
    if [ -z "$ssh_output" ]; then
        log_error "No backup files found in $backup_dir or failed to connect to source server"
    fi
    
    echo "$ssh_output"
}

# Function to transfer file with retries
transfer_file() {
    local src="$1"
    local dest="$2"
    local attempts=0
    
    while [ $attempts -lt "$MAX_RETRIES" ]; do
        attempts=$((attempts + 1))
        log_info "Transfer attempt $attempts of $MAX_RETRIES: $src to $dest"
        
        if scp -o ConnectTimeout=30 -o ConnectionAttempts=3 "$src" "$dest"; then
            return 0
        fi
        
        if [ $attempts -lt "$MAX_RETRIES" ]; then
            log_warning "Transfer failed, retrying in $RETRY_DELAY seconds..."
            sleep "$RETRY_DELAY"
        fi
    done
    
    return 1
}

# Function to execute remote command with retries
execute_remote() {
    local host="$1"
    local cmd="$2"
    local attempts=0
    
    while [ $attempts -lt "$MAX_RETRIES" ]; do
        attempts=$((attempts + 1))
        log_info "Remote execution attempt $attempts of $MAX_RETRIES on $host"
        
        if ssh -o ConnectTimeout=30 -o ConnectionAttempts=3 "$host" "$cmd"; then
            return 0
        fi
        
        if [ $attempts -lt "$MAX_RETRIES" ]; then
            log_warning "Remote command failed, retrying in $RETRY_DELAY seconds..."
            sleep "$RETRY_DELAY"
        fi
    done
    
    return 1
}

# Function to run in tmux session
run_in_tmux() {
    if ! command_exists tmux; then
        log_error "tmux is not installed. Please install it or run without --detach"
    fi

    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        log_warning "tmux session $SESSION_NAME already exists. Attaching to it."
        tmux attach -t "$SESSION_NAME"
        return
    fi

    log_info "Starting new tmux session: $SESSION_NAME"
    tmux new-session -d -s "$SESSION_NAME" "bash $0 \
        --source-user '$SOURCE_USER' \
        --source-ip '$SOURCE_IP' \
        --source-dir '$SOURCE_DIR' \
        --target-user '$TARGET_USER' \
        --target-ip '$TARGET_IP' \
        --target-dir '$TARGET_DIR' \
        --mysql-user '$MYSQL_USER' \
        --mysql-pass '$MYSQL_PASS' \
        --new-db-name '$NEW_DB_NAME' \
        --env-file '$ENV_FILE' \
        --db-var '$DB_NAME_VAR' \
        --max-retries '$MAX_RETRIES' \
        --retry-delay '$RETRY_DELAY' \
        2>&1 | tee -a '$LOG_FILE'"

    log_info "Script is running in detached tmux session."
    log_info "To attach: tmux attach -t $SESSION_NAME"
    log_info "To check logs: tail -f $LOG_FILE"
    exit 0
}

# Parse command line arguments
DETACH=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-user)
            SOURCE_USER="$2"
            shift 2
            ;;
        --source-ip)
            SOURCE_IP="$2"
            shift 2
            ;;
        --source-dir)
            SOURCE_DIR="$2"
            shift 2
            ;;
        --target-user)
            TARGET_USER="$2"
            shift 2
            ;;
        --target-ip)
            TARGET_IP="$2"
            shift 2
            ;;
        --target-dir)
            TARGET_DIR="$2"
            shift 2
            ;;
        --mysql-user)
            MYSQL_USER="$2"
            shift 2
            ;;
        --mysql-pass)
            MYSQL_PASS="$2"
            shift 2
            ;;
        --new-db-name)
            NEW_DB_NAME="$2"
            shift 2
            ;;
        --env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        --db-var)
            DB_NAME_VAR="$2"
            shift 2
            ;;
        --max-retries)
            MAX_RETRIES="$2"
            shift 2
            ;;
        --retry-delay)
            RETRY_DELAY="$2"
            shift 2
            ;;
        --config)
            load_config "$2"
            shift 2
            ;;
        --detach)
            DETACH=1
            shift
            ;;
        --version)
            echo "MySQL Backup Transfer and Restore Script v$VERSION"
            exit 0
            ;;
        --help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            ;;
    esac
done

# Set default values if not provided
SOURCE_USER=${SOURCE_USER:-$DEFAULT_SOURCE_USER}
SOURCE_IP=${SOURCE_IP:-$DEFAULT_SOURCE_IP}
SOURCE_DIR=${SOURCE_DIR:-$DEFAULT_SOURCE_DIR}
TARGET_USER=${TARGET_USER:-$DEFAULT_TARGET_USER}
TARGET_IP=${TARGET_IP:-$DEFAULT_TARGET_IP}
TARGET_DIR=${TARGET_DIR:-$DEFAULT_TARGET_DIR}
MYSQL_USER=${MYSQL_USER:-$DEFAULT_MYSQL_USER}
MYSQL_PASS=${MYSQL_PASS:-$DEFAULT_MYSQL_PASS}
NEW_DB_NAME=${NEW_DB_NAME:-$DEFAULT_NEW_DB_NAME}
ENV_FILE=${ENV_FILE:-$DEFAULT_ENV_FILE}
DB_NAME_VAR=${DB_NAME_VAR:-$DEFAULT_DB_NAME_VAR}
MAX_RETRIES=${MAX_RETRIES:-$DEFAULT_MAX_RETRIES}
RETRY_DELAY=${RETRY_DELAY:-$DEFAULT_RETRY_DELAY}

# Main script execution
if [ $DETACH -eq 1 ]; then
    run_in_tmux
fi

log_info "Starting MySQL backup transfer and restore process"
log_info "Log file: $LOG_FILE"
log_info "Source: ${SOURCE_USER}@${SOURCE_IP}:${SOURCE_DIR}"
log_info "Target: ${TARGET_USER}@${TARGET_IP}:${TARGET_DIR}"
log_info "New database name: $NEW_DB_NAME"

# Step 1: Find the latest backup file
BACKUP_FILE=$(find_latest_backup "$SOURCE_DIR")
BACKUP_FILENAME=$(basename "$BACKUP_FILE")
log_info "Found latest backup: $BACKUP_FILE"

# Step 2: Transfer the backup to target VM
transfer_file "${SOURCE_USER}@${SOURCE_IP}:${BACKUP_FILE}" "${TARGET_USER}@${TARGET_IP}:${TARGET_DIR}/" ||
    log_error "Failed to transfer backup file after $MAX_RETRIES attempts"

# Step 3: Prepare remote command
REMOTE_CMD=$(cat << EOF
# Set up logging
exec > >(tee -a "/tmp/remote_${LOG_FILE}") 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting database restoration"

# Change to target directory
cd "$TARGET_DIR" || { echo "Failed to change to target directory"; exit 1; }

# Unzip the backup (if compressed)
if [[ "$BACKUP_FILENAME" == *.gz ]]; then
    echo "Unzipping $BACKUP_FILENAME..."
    gunzip -f "$BACKUP_FILENAME" || { echo "Failed to unzip backup"; exit 1; }
    UNZIPPED_FILE="${BACKUP_FILENAME%.gz}"
else
    UNZIPPED_FILE="$BACKUP_FILENAME"
fi

# Verify unzipped file exists
if [ ! -f "\$UNZIPPED_FILE" ]; then
    echo "Backup file not found: \$UNZIPPED_FILE"
    exit 1
fi

# Create the new database
echo "Creating database $NEW_DB_NAME..."
mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "CREATE DATABASE IF NOT EXISTS \`$NEW_DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || { echo "Failed to create database"; exit 1; }

# Import the data
echo "Importing data to $NEW_DB_NAME..."
mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" "$NEW_DB_NAME" < "\$UNZIPPED_FILE" || { echo "Failed to import data"; exit 1; }

# Verify import
RECORD_COUNT=\$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$NEW_DB_NAME';")
if [ "\$RECORD_COUNT" -eq 0 ]; then
    echo "Warning: No tables found in the new database"
fi

# Update .env file if it exists
if [ -f "$ENV_FILE" ]; then
    echo "Updating $ENV_FILE..."
    if grep -q "^$DB_NAME_VAR=" "$ENV_FILE"; then
        sed -i "s/^$DB_NAME_VAR=.*/$DB_NAME_VAR=$NEW_DB_NAME/" "$ENV_FILE" || { echo "Failed to update .env file"; exit 1; }
        echo "Updated $DB_NAME_VAR in $ENV_FILE to $NEW_DB_NAME"
    else
        echo "$DB_NAME_VAR=$NEW_DB_NAME" >> "$ENV_FILE"
        echo "Added $DB_NAME_VAR to $ENV_FILE"
    fi
else
    echo "Warning: .env file not found at $ENV_FILE"
fi

# Clean up (optional)
# rm -f "\$UNZIPPED_FILE"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Database restoration completed successfully"
EOF
)

# Execute remote command
execute_remote "${TARGET_USER}@${TARGET_IP}" "$REMOTE_CMD" ||
    log_error "Database restoration failed on target VM after $MAX_RETRIES attempts"

log_info "Database restoration completed successfully!"
log_info "New database name: $NEW_DB_NAME"
log_info "You can verify the import by running:"
log_info "mysql -u $MYSQL_USER -p'$MYSQL_PASS' $NEW_DB_NAME -e 'SHOW TABLES;'"
exit 0