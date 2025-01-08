#!/bin/bash

# 设置错误处理
set -e

# 日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

success_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

error_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >&2
}

# 检查环境变量
check_environment() {
    log "🔍 检查环境变量..."
    
    # 检查必要的环境变量
    if [ -z "$BW_HOST" ]; then
        error_log "❌ 未设置 BW_HOST"
        return 1
    fi
    # 只显示域名的第一部分
    log "✅ BW_HOST: $(echo "$BW_HOST" | sed -E 's|^(https?://)?([^/]*?\.)?([^./]+\.[^./]+).*|https://***.\3|')"

    if [ -z "$BW_EMAIL" ]; then
        error_log "❌ 未设置 BW_EMAIL"
        return 1
    fi
    log "✅ BW_EMAIL: $(echo "$BW_EMAIL" | sed 's/\([^@]*\)@.*/\1@.../')"

    if [ -z "$BW_PASSWORD" ]; then
        error_log "❌ 未设置 BW_PASSWORD"
        return 1
    fi
    log "✅ BW_PASSWORD: ********"

    if [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
        error_log "❌ 未设置 BACKUP_ENCRYPTION_KEY"
        return 1
    fi
    log "✅ BACKUP_ENCRYPTION_KEY: ********"

    if [ -z "$BACKUP_FORMAT" ]; then
        BACKUP_FORMAT="json"
    fi
    log "✅ BACKUP_FORMAT: $BACKUP_FORMAT"

    # 检查自动解密选项
    if [ -z "$AUTO_DECRYPT" ]; then
        AUTO_DECRYPT="false"
    fi
    log "✅ AUTO_DECRYPT: $AUTO_DECRYPT"

    return 0
}

# 初始化变量
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=${BACKUP_DIR:-/backup}
BACKUP_FILE="$BACKUP_DIR/bitwarden_export_$TIMESTAMP.$BACKUP_FORMAT"
ENCRYPTED_FILE="$BACKUP_FILE.gpg"

# 清理之前的会话
log "🧹 清理之前的会话..."
bw logout >/dev/null 2>&1 || true

# 检查环境变量
check_environment || exit 1

# 连接到服务器
log "🔗 连接到 Bitwarden 服务器..."

# 检查网络连接
log "🌐 检查网络连接..."
if ! ping -c 1 ${BW_HOST#*//} >/dev/null 2>&1; then
    error_log "❌ 网络连接失败"
    exit 1
fi

# 检查DNS解析
log "🔍 检查 DNS 解析..."
if ! nslookup ${BW_HOST#*//} >/dev/null 2>&1; then
    error_log "❌ DNS解析失败"
    exit 1
fi

# 检查HTTPS连接
log "🔒 检查 HTTPS 连接..."
if ! curl -s -o /dev/null -w '%{http_code}' $BW_HOST | grep -q '200\|301\|302'; then
    error_log "❌ 无法连接到服务器"
    exit 1
fi

success_log "✨ 服务器连接成功！"

# 登录到Bitwarden
log "🔑 登录到 Bitwarden..."
if ! BW_SESSION=$(bw login "$BW_EMAIL" "$BW_PASSWORD" --raw); then
    error_log "❌ 登录失败"
    exit 1
fi
export BW_SESSION
success_log "✨ 登录成功！"

# 解锁密码库
log "🔓 解锁密码库..."
if ! BW_SESSION=$(echo "$BW_PASSWORD" | bw unlock --raw); then
    error_log "❌ 解锁失败"
    exit 1
fi
export BW_SESSION
success_log "✨ 密码库已解锁"

# 检查会话状态
log "🔍 检查会话状态..."
if ! bw status --session "$BW_SESSION" | grep -q '"status":"unlocked"'; then
    error_log "❌ 密码库未解锁"
    exit 1
fi
success_log "✨ 密码库状态正常"

# 同步数据
log "🔄 同步数据..."
if ! bw sync --session "$BW_SESSION"; then
    error_log "❌ 同步失败"
    exit 1
fi
success_log "✨ 数据同步完成"

# 导出数据
log "📤 导出数据..."

# 确保目标目录存在且有正确的权限
mkdir -p "$BACKUP_DIR"
chmod 777 "$BACKUP_DIR"

# 创建空文件并设置权限
touch "$BACKUP_FILE"
chmod 666 "$BACKUP_FILE"

# 导出数据
ERROR_LOG=$(mktemp)
log "📁 尝试导出到: $BACKUP_FILE"
if ! bw export --format "$BACKUP_FORMAT" --output "$BACKUP_FILE" --session "$BW_SESSION" 2>"$ERROR_LOG"; then
    ERROR_MSG=$(cat "$ERROR_LOG")
    error_log "❌ 导出失败: $ERROR_MSG"
    rm -f "$BACKUP_FILE" "$ERROR_LOG"
    exit 1
fi
rm -f "$ERROR_LOG"

# 检查导出文件大小
EXPORT_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null)
if [ -z "$EXPORT_SIZE" ] || [ "$EXPORT_SIZE" -lt 1000 ]; then
    error_log "❌ 导出文件大小异常: ${EXPORT_SIZE:-0} bytes"
    rm -f "$BACKUP_FILE"
    exit 1
fi

log "📊 导出文件大小: $(ls -lh "$BACKUP_FILE" | awk '{print $5}')"
success_log "✨ 导出完成"

# 根据 AUTO_DECRYPT 决定是否加密
if [ "$AUTO_DECRYPT" = "true" ]; then
    log "🔓 自动解密模式：保留原始文件"
    success_log "✨ 备份完成！已保存到: $BACKUP_FILE"
else
    # 加密备份文件
    log "🔐 加密备份文件..."
    if [ ! -f "$BACKUP_FILE" ]; then
        error_log "❌ 加密失败: 备份文件不存在"
        exit 1
    fi

    # 使用GPG加密
    if ! echo "$BACKUP_ENCRYPTION_KEY" | gpg --batch --yes --passphrase-fd 0 \
        --symmetric --cipher-algo AES256 \
        --output "$ENCRYPTED_FILE" "$BACKUP_FILE"; then
        error_log "❌ 加密失败"
        rm -f "$ENCRYPTED_FILE"
        exit 1
    fi

    # 只有在加密成功后才删除原始文件
    if [ -f "$ENCRYPTED_FILE" ]; then
        rm -f "$BACKUP_FILE"
        log "📊 加密文件大小: $(ls -lh "$ENCRYPTED_FILE" | awk '{print $5}')"
        success_log "✨ 加密完成"
        success_log "✨ 备份完成！已保存到: $ENCRYPTED_FILE"
    fi
fi

# 清理旧备份
log "🧹 清理旧备份..."
if [ "$AUTO_DECRYPT" = "true" ]; then
    # 清理旧的原始文件，保留最新的
    if [ -n "$BACKUP_RETENTION_DAYS" ]; then
        find "$BACKUP_DIR" -name "bitwarden_export_*.$BACKUP_FORMAT" -type f -mtime +"$BACKUP_RETENTION_DAYS" -delete
    fi
    # 删除所有加密文件
    find "$BACKUP_DIR" -name "*.gpg" -type f -delete
else
    # 清理所有原始文件
    find "$BACKUP_DIR" -name "bitwarden_export_*.$BACKUP_FORMAT" -type f -delete
    # 清理旧的加密文件
    if [ -n "$BACKUP_RETENTION_DAYS" ]; then
        find "$BACKUP_DIR" -name "*.gpg" -type f -mtime +"$BACKUP_RETENTION_DAYS" -delete
    fi
fi
success_log "✨ 旧备份清理完成"
