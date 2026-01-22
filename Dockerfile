ARG FRM='pihole/pihole:latest'
ARG TAG='latest'

FROM ${FRM}
ARG FRM
ARG TAG
ARG TARGETPLATFORM

USER root

# Install dependencies via Alpine's apk (replaces apt-get)
RUN apk add --no-cache \
        bash \
        sudo \
        nano \
        curl \
        wget \
        git \
        php \
        php-cli \
        php-pdo_sqlite \
        php-intl \
        php-curl \
        php-openssl \
        php-pcntl \
        php-posix

# Add your scripts
ADD stuff /temp

# Run install script (dnsproxy + cache-domains)
RUN /bin/bash /temp/install.sh \
    && rm -rf /temp

# Pi-hole updatelists
RUN wget -O - https://raw.githubusercontent.com/jacklul/pihole-updatelists/master/install.sh | bash /dev/stdin docker

# Build info
RUN echo "$(date "+%d.%m.%Y %T") Built from ${FRM} with tag ${TAG}" >> /build_date.info
