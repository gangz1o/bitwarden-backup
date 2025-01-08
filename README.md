# Bitwarden Backup

[English](#english) | [中文](#中文)

## English

### Introduction

A Docker-based automated backup solution for Bitwarden vault. It supports encrypted backups with GPG and can be easily deployed on Synology NAS or any Docker-capable system.

### Features

- 🔄 Automated periodic backups
- 🔐 GPG encryption support
- 📦 Multiple export formats (json/csv)
- 🧹 Automatic cleanup of old backups
- 🔍 Detailed logging with emojis
- 🌏 Timezone support
- 🔒 Sensitive information masking

### Prerequisites

- Docker or Docker Compose
- Bitwarden account
- GPG (for encryption)

### Environment Variables

| Variable              | Description                   | Required | Default        |
| --------------------- | ----------------------------- | -------- | -------------- |
| BW_HOST               | Bitwarden server URL          | Yes      | -              |
| BW_EMAIL              | Bitwarden account email       | Yes      | -              |
| BW_PASSWORD           | Bitwarden account password    | Yes      | -              |
| BACKUP_ENCRYPTION_KEY | GPG encryption key            | Yes      | -              |
| BACKUP_FORMAT         | Export format (json/csv)      | No       | json           |
| BACKUP_RETENTION_DAYS | Days to keep backups          | No       | 7              |
| BACKUP_SCHEDULE       | Backup schedule (cron format) | No       | 0 */8 * * *    |
| AUTO_DECRYPT          | Keep unencrypted files        | No       | false          |

### Deployment

#### Using Docker

```bash
docker run -d \
  -e BW_HOST=https://your-bitwarden-server \
  -e BW_EMAIL=your-email@example.com \
  -e BW_PASSWORD=your-password \
  -e BACKUP_ENCRYPTION_KEY=your-encryption-key \
  -e BACKUP_FORMAT=json \
  -e BACKUP_RETENTION_DAYS=7 \
  -e AUTO_DECRYPT=false \
  -v /path/to/backup:/backup \
  gangz1o/bitwarden-backup:latest
```

#### Using Docker Compose

1. Create a `.env` file:

```env
BW_HOST=https://your-bitwarden-server
BW_EMAIL=your-email@example.com
BW_PASSWORD=your-password
BACKUP_ENCRYPTION_KEY=your-encryption-key
BACKUP_FORMAT=json
BACKUP_RETENTION_DAYS=7
AUTO_DECRYPT=false
```

2. Run with docker-compose:

```bash
docker-compose up -d
```

### License

MIT License - see [LICENSE](LICENSE) file for details

---

## 中文

### 简介

基于 Docker 的 Bitwarden 密码库自动备份解决方案。支持 GPG 加密备份，可以轻松部署在群晖 NAS 或任何支持 Docker 的系统上。

### 特性

- 🔄 自动定期备份
- 🔐 支持 GPG 加密
- 📦 多种导出格式（json/csv）
- 🧹 自动清理旧备份
- 🔍 详细的日志（带表情符号）
- 🌏 时区支持
- 🔒 敏感信息脱敏

### 前置要求

- Docker 或 Docker Compose
- Bitwarden 账户
- GPG（用于加密）

### 环境变量

| 变量                  | 说明                  | 必需 | 默认值         |
| --------------------- | --------------------- | ---- | -------------- |
| BW_HOST               | Bitwarden 服务器地址  | 是   | -              |
| BW_EMAIL              | Bitwarden 账户邮箱    | 是   | -              |
| BW_PASSWORD           | Bitwarden 账户密码    | 是   | -              |
| BACKUP_ENCRYPTION_KEY | GPG 加密密钥          | 是   | -              |
| BACKUP_FORMAT         | 导出格式（json/csv）  | 否   | json           |
| BACKUP_RETENTION_DAYS | 备份保留天数          | 否   | 7              |
| BACKUP_SCHEDULE       | 备份计划（cron 格式） | 否   | 0 */8 * * *    |
| AUTO_DECRYPT          | 保留未加密文件        | 否   | false          |

### 部署方式

#### 使用 Docker

```bash
docker run -d \
  -e BW_HOST=https://your-bitwarden-server \
  -e BW_EMAIL=your-email@example.com \
  -e BW_PASSWORD=your-password \
  -e BACKUP_ENCRYPTION_KEY=your-encryption-key \
  -e BACKUP_FORMAT=json \
  -e BACKUP_RETENTION_DAYS=7 \
  -e AUTO_DECRYPT=false \
  -v /path/to/backup:/backup \
  gangz1o/bitwarden-backup:latest
```

#### 使用 Docker Compose

1. 创建 `.env` 文件：

```env
BW_HOST=https://your-bitwarden-server
BW_EMAIL=your-email@example.com
BW_PASSWORD=your-password
BACKUP_ENCRYPTION_KEY=your-encryption-key
BACKUP_FORMAT=json
BACKUP_RETENTION_DAYS=7
AUTO_DECRYPT=false
```

2. 运行 docker-compose：

```bash
docker-compose up -d
```

### 开源协议

MIT 许可证 - 详见 [LICENSE](LICENSE) 文件
