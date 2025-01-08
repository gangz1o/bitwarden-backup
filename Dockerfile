FROM --platform=linux/amd64 debian:bullseye-slim as builder

# 安装必要的软件包
RUN apt-get update && apt-get install -y --no-install-recommends \
  curl \
  unzip \
  ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  # 下载并安装 Bitwarden CLI
  && curl -L "https://vault.bitwarden.com/download/?app=cli&platform=linux" -o bw.zip \
  && unzip bw.zip \
  && chmod +x bw \
  && rm bw.zip

FROM --platform=linux/amd64 debian:bullseye-slim

# 设置默认环境变量
ENV BW_HOST=https://vault.bitwarden.com \
  BW_EMAIL= \
  BW_PASSWORD= \
  BACKUP_ENCRYPTION_KEY= \
  BACKUP_FORMAT=json \
  BACKUP_RETENTION_DAYS=7 \
  AUTO_DECRYPT=false \
  BACKUP_SCHEDULE="*/3 * * * *" \
  TZ=Asia/Shanghai \
  LANG=en_US.UTF-8 \
  LANGUAGE=en_US:en \
  LC_ALL=en_US.UTF-8

# 安装必要的软件包并设置本地化
RUN apt-get update && apt-get install -y --no-install-recommends \
  jq \
  gpg \
  gpg-agent \
  cron \
  locales \
  tzdata \
  iputils-ping \
  dnsutils \
  curl \
  ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen \
  && mkdir -p /backups \
  && touch /var/log/cron.log \
  && chmod 0644 /var/log/cron.log

# 设置时区
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 从构建阶段复制 Bitwarden CLI
COPY --from=builder /bw /usr/local/bin/bw

# 复制备份脚本
COPY scripts/backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

# 创建启动脚本
RUN echo '#!/bin/bash\n\
# 导出必要的环境变量到容器环境文件\n\
(\n\
echo "BW_HOST=$BW_HOST"\n\
echo "BW_EMAIL=$BW_EMAIL"\n\
echo "BW_PASSWORD=$BW_PASSWORD"\n\
echo "BACKUP_ENCRYPTION_KEY=$BACKUP_ENCRYPTION_KEY"\n\
echo "BACKUP_FORMAT=$BACKUP_FORMAT"\n\
echo "BACKUP_RETENTION_DAYS=$BACKUP_RETENTION_DAYS"\n\
echo "BACKUP_SCHEDULE=\"$BACKUP_SCHEDULE\""\n\
echo "AUTO_DECRYPT=$AUTO_DECRYPT"\n\
echo "TZ=$TZ"\n\
echo "LANG=$LANG"\n\
echo "LANGUAGE=$LANGUAGE"\n\
echo "LC_ALL=$LC_ALL"\n\
echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"\n\
) > /container.env\n\
chmod 600 /container.env\n\
\n\
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-*/3 * * * *}"\n\
echo "SHELL=/bin/bash\nBASH_ENV=/container.env\nPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n${BACKUP_SCHEDULE} /usr/local/bin/backup.sh >> /var/log/cron.log 2>&1" > /etc/cron.d/backup-cron\n\
chmod 0644 /etc/cron.d/backup-cron\n\
crontab /etc/cron.d/backup-cron\n\
\n\
echo "🚀 执行初始备份..."\n\
. /container.env && /usr/local/bin/backup.sh\n\
\n\
echo "⏰ 启动定时任务服务 ($BACKUP_SCHEDULE)..."\n\
crontab -l\n\
service cron start\n\
\n\
service cron status\n\
\n\
tail -f /var/log/cron.log' > /start.sh && chmod +x /start.sh

WORKDIR /app

CMD ["/start.sh"]
