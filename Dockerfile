#---------------------------------------
# Base image
#---------------------------------------
ARG FRM='pihole/pihole:latest'
ARG TAG='latest'
ARG TARGETPLATFORM
FROM ${FRM}

# Re-declare TARGETPLATFORM for use in RUN commands (BuildKit requirement)
ARG TARGETPLATFORM

USER root

#---------------------------------------
# Install dependencies
#---------------------------------------
RUN apk add --no-cache \
        bash \
        curl \
        wget \
        git \
        sudo \
        nano \
        php \
        php-curl \
        php-intl \
        php-openssl \
        php-pcntl \
        php-posix \
        php-pdo_sqlite

#---------------------------------------
# Install dnsproxy + pihole-updatelists + cache-domains
#---------------------------------------
COPY stuff /temp
RUN chmod +x /temp/install.sh \
    && TARGETPLATFORM=${TARGETPLATFORM} /bin/bash /temp/install.sh \
    && wget -O - https://raw.githubusercontent.com/jacklul/pihole-updatelists/master/install.sh | bash -s docker \
    && rm -rf /temp

#---------------------------------------
# Bake default lancache cron into /crontab.txt
# Default schedule: 4:17 AM daily (override at runtime via LANCACHE_CRONTAB_STRING env var)
# pihole-updatelists schedule: override via CRONTAB_STRING env var (already handled by its docker.sh)
#---------------------------------------
RUN echo "17 4 * * * root PATH=\"/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\" /usr/local/bin/lancache-dns-updates.sh >/var/log/lancache-dns-updates-cron.log 2>&1" >> /crontab.txt \
    && echo "$(date "+%d.%m.%Y %T") Built from ${FRM} with tag ${TAG}" >> /build_date.info

#---------------------------------------
# Use Pi-hole's default entrypoint
#---------------------------------------
