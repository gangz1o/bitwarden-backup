#!/bin/bash

# Set error handling
set -e

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

success_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

error_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >&2
}

# Check environment variables
check_environment() {
    log "🔍 Checking environment variables..."
    
    # Check required environment variables
    if [ -z "$BW_HOST" ]; then
        error_log "❌ BW_HOST not set"
        return 1
    fi
    # Only show the first part of the domain
    log "✅ BW_HOST: $(echo "$BW_HOST" | sed -E 's|^(https?://)?([^/]*?\.)?([^./]+\.[^./]+).*|https://***.\3|')"

    if [ -z "$BW_EMAIL" ]; then
        error_log "❌ BW_EMAIL not set"
        return 1
    fi
    log "✅ BW_EMAIL: $(echo "$BW_EMAIL" | sed 's/\([^@]*\)@.*/\1@.../')"

    if [ -z "$BW_PASSWORD" ]; then
        error_log "❌ BW_PASSWORD not set"
        return 1
    fi
    log "✅ BW_PASSWORD: ********"

    if [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
        error_log "❌ BACKUP_ENCRYPTION_KEY not set"
        return 1
    fi
    log "✅ BACKUP_ENCRYPTION_KEY: ********"

    if [ -z "$BACKUP_FORMAT" ]; then
        BACKUP_FORMAT="json"
    fi
    log "✅ BACKUP_FORMAT: $BACKUP_FORMAT"

    # Check auto-decrypt option
    if [ -z "$AUTO_DECRYPT" ]; then
        AUTO_DECRYPT="false"
    fi
    log "✅ AUTO_DECRYPT: $AUTO_DECRYPT"

    return 0
}

# Initialize variables
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=${BACKUP_DIR:-/backup}
BACKUP_FILE="$BACKUP_DIR/bitwarden_export_$TIMESTAMP.$BACKUP_FORMAT"
ENCRYPTED_FILE="$BACKUP_FILE.gpg"

# Clean up previous sessions
log "🧹 Cleaning up previous sessions..."
bw logout >/dev/null 2>&1 || true

# Check environment variables
check_environment || exit 1

# Connect to server
log "🔗 Connecting to Bitwarden server..."

# Check network connection
log "🌐 Checking network connection..."
if ! ping -c 1 ${BW_HOST#*//} >/dev/null 2>&1; then
    error_log "❌ Network connection failed"
    exit 1
fi

# Check DNS resolution
log "🔍 Checking DNS resolution..."
if ! nslookup ${BW_HOST#*//} >/dev/null 2>&1; then
    error_log "❌ DNS resolution failed"
    exit 1
fi

# Check HTTPS connection
log "🔒 Checking HTTPS connection..."
if ! curl -s -o /dev/null -w '%{http_code}' $BW_HOST | grep -q '200\|301\|302'; then
    error_log "❌ Cannot connect to server"
    exit 1
fi

success_log "✨ Server connection successful!"

# Login to Bitwarden
log "🔑 Logging in to Bitwarden..."
if ! BW_SESSION=$(bw login "$BW_EMAIL" "$BW_PASSWORD" --raw); then
    error_log "❌ Login failed"
    exit 1
fi
export BW_SESSION
success_log "✨ Login successful!"

# Unlock vault
log "🔓 Unlocking vault..."
if ! BW_SESSION=$(echo "$BW_PASSWORD" | bw unlock --raw); then
    error_log "❌ Unlock failed"
    exit 1
fi
export BW_SESSION
success_log "✨ Vault unlocked"

# Check session status
log "🔍 Checking session status..."
if ! bw status --session "$BW_SESSION" | grep -q '"status":"unlocked"'; then
    error_log "❌ Vault not unlocked"
    exit 1
fi
success_log "✨ Vault status normal"

# Sync data
log "🔄 Syncing data..."
if ! bw sync --session "$BW_SESSION"; then
    error_log "❌ Sync failed"
    exit 1
fi
success_log "✨ Data sync complete"

# Export data
log "📤 Exporting data..."

# Ensure target directory exists with correct permissions
mkdir -p "$BACKUP_DIR"
chmod 777 "$BACKUP_DIR"

# Create empty file and set permissions
touch "$BACKUP_FILE"
chmod 666 "$BACKUP_FILE"

# Export data
ERROR_LOG=$(mktemp)
log "📁 Attempting to export to: $BACKUP_FILE"
if ! bw export --format "$BACKUP_FORMAT" --output "$BACKUP_FILE" --session "$BW_SESSION" 2>"$ERROR_LOG"; then
    ERROR_MSG=$(cat "$ERROR_LOG")
    error_log "❌ Export failed: $ERROR_MSG"
    rm -f "$BACKUP_FILE" "$ERROR_LOG"
    exit 1
fi
rm -f "$ERROR_LOG"

# Check export file size
EXPORT_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null)
if [ -z "$EXPORT_SIZE" ] || [ "$EXPORT_SIZE" -lt 1000 ]; then
    error_log "❌ Export file size abnormal: ${EXPORT_SIZE:-0} bytes"
    rm -f "$BACKUP_FILE"
    exit 1
fi

log "📊 Export file size: $(ls -lh "$BACKUP_FILE" | awk '{print $5}')"
success_log "✨ Export complete"

# Decide whether to encrypt based on AUTO_DECRYPT
if [ "$AUTO_DECRYPT" = "true" ]; then
    log "🔓 Auto-decrypt mode: keeping original file"
    success_log "✨ Backup complete! Saved to: $BACKUP_FILE"
else
    # Encrypt backup file
    log "🔐 Encrypting backup file..."
    if [ ! -f "$BACKUP_FILE" ]; then
        error_log "❌ Encryption failed: backup file does not exist"
        exit 1
    fi

    # Use GPG for encryption
    if ! echo "$BACKUP_ENCRYPTION_KEY" | gpg --batch --yes --passphrase-fd 0 \
        --symmetric --cipher-algo AES256 \
        --output "$ENCRYPTED_FILE" "$BACKUP_FILE"; then
        error_log "❌ Encryption failed"
        rm -f "$ENCRYPTED_FILE"
        exit 1
    fi

    # Only delete original file after successful encryption
    if [ -f "$ENCRYPTED_FILE" ]; then
        rm -f "$BACKUP_FILE"
        log "📊 Encrypted file size: $(ls -lh "$ENCRYPTED_FILE" | awk '{print $5}')"
        success_log "✨ Encryption complete"
        success_log "✨ Backup complete! Saved to: $ENCRYPTED_FILE"
    fi
fi

# Clean up old backups
log "🧹 Cleaning up old backups..."
if [ "$AUTO_DECRYPT" = "true" ]; then
    # Clean up old original files, keep the latest
    if [ -n "$BACKUP_RETENTION_DAYS" ]; then
        find "$BACKUP_DIR" -name "bitwarden_export_*.$BACKUP_FORMAT" -type f -mtime +"$BACKUP_RETENTION_DAYS" -delete
    fi
    # Delete all encrypted files
    find "$BACKUP_DIR" -name "*.gpg" -type f -delete
else
    # Clean up all original files
    find "$BACKUP_DIR" -name "bitwarden_export_*.$BACKUP_FORMAT" -type f -delete
    # Clean up old encrypted files
    if [ -n "$BACKUP_RETENTION_DAYS" ]; then
        find "$BACKUP_DIR" -name "*.gpg" -type f -mtime +"$BACKUP_RETENTION_DAYS" -delete
    fi
fi
success_log "✨ Old backups cleaned up"
