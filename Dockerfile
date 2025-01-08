FROM --platform=linux/amd64 debian:bullseye-slim as builder

# Install necessary packages
RUN apt-get update && apt-get install -y --no-install-recommends \
  curl \
  unzip \
  ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  # Download and install Bitwarden CLI
  && curl -L "https://vault.bitwarden.com/download/?app=cli&platform=linux" -o bw.zip \
  && unzip bw.zip \
  && chmod +x bw \
  && rm bw.zip

FROM --platform=linux/amd64 debian:bullseye-slim

# Set default environment variables
ENV BW_HOST=https://vault.bitwarden.com \
  BW_EMAIL= \
  BW_PASSWORD= \
  BACKUP_ENCRYPTION_KEY= \
  BACKUP_FORMAT=json \
  BACKUP_RETENTION_DAYS=7 \
  AUTO_DECRYPT=false \
  BACKUP_SCHEDULE="0 */8 * * *" \
  TZ=Asia/Shanghai \
  LANG=en_US.UTF-8 \
  LANGUAGE=en_US:en \
  LC_ALL=en_US.UTF-8

# Install necessary packages and set localization
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

# Set timezone
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Copy Bitwarden CLI from builder stage
COPY --from=builder /bw /usr/local/bin/bw

# Copy backup script
COPY scripts/backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

# Create startup script
RUN echo '#!/bin/bash\n\
# Export necessary environment variables to container env file\n\
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
echo "🚀 Running initial backup..."\n\
. /container.env && /usr/local/bin/backup.sh\n\
\n\
echo "⏰ Starting cron service ($BACKUP_SCHEDULE)..."\n\
crontab -l\n\
service cron start\n\
\n\
service cron status\n\
\n\
tail -f /var/log/cron.log' > /start.sh && chmod +x /start.sh

WORKDIR /app

CMD ["/start.sh"]
