# MySQL Backup Transfer and Restore Script

A robust Bash script to transfer MySQL backups between servers and restore them automatically.

## Features

- 🚀 Automatic transfer of MySQL backups between servers
- 🔄 Finds and uses the latest backup file
- 🛡️ Resilient to network interruptions (runs in tmux)
- 📝 Comprehensive logging
- ⚙️ Fully configurable via command line or config file
- 🔄 Automatic .env file updating

## Quick Start

```bash
# Clone the repository
git clone https://github.com/Soulaimaneelhourre/Mysql-Backup-Restore.git
cd Mysql-Backup-Restore

# Make the script executable
chmod +x mysql_restore.sh

# Run with basic options
./mysql_restore.sh \
    --source-user admin \
    --source-ip 192.168.1.100 \
    --source-dir /backups/mysql \
    --target-user deploy \
    --target-ip 192.168.1.200 \
    --mysql-user root \
    --mysql-pass "securepassword" \
    --detach