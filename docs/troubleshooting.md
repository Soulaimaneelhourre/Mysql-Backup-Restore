
### docs/troubleshooting.md

```markdown
# Troubleshooting Guide

## Common Issues

### 1. SSH Connection Problems

**Symptoms**: Script fails with SSH connection errors

**Solutions**:
- Ensure key-based authentication is set up
- Test SSH connection manually first
- Use `-v` flag with SSH commands to debug

### 2. Backup File Not Found

**Symptoms**: "No backup files found" error

**Solutions**:
- Verify the source directory path
- Check backup file naming pattern
- Ensure files have proper permissions

### 3. MySQL Permission Issues

**Symptoms**: Database creation or import fails

**Solutions**:
- Verify MySQL user has CREATE DATABASE privileges
- Check if database already exists
- Test MySQL connection manually

## Debugging Tips

1. Check the log file (`mysql_restore_*.log`)
2. Run script without `--detach` to see real-time output
3. Add `-v` flag to SSH commands in script for more verbose output
4. Test each step manually (SSH, SCP, MySQL commands)