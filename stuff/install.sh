#!/bin/bash


# clean stubby config
mkdir -p /etc/stubby \
    && rm -f /etc/stubby/stubby.yml

DETECTED_ARCH=$(dpkg --print-architecture)

# install cloudflared
mkdir -p /tmp \
    && cd /tmp
if [[ ${TARGETPLATFORM} =~ "arm64" ]]
then
    curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb -o /tmp/cloudflared.deb
    dpkg --add-architecture arm64
    echo "$(date "+%d.%m.%Y %T") Added cloudflared for ${TARGETPLATFORM}" >> /build.info
elif [[ ${TARGETPLATFORM} =~ "amd64" ]]
then 
    curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb
    dpkg --add-architecture amd64
    echo "$(date "+%d.%m.%Y %T") Added cloudflared for ${TARGETPLATFORM}" >> /build.info
elif [[ ${TARGETPLATFORM} =~ "386" ]]
then
    curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-386.deb -o /tmp/cloudflared.deb
    dpkg --add-architecture 386
    echo "$(date "+%d.%m.%Y %T") Added cloudflared for ${TARGETPLATFORM}" >> /build.info
elif [[ ${TARGETPLATFORM} =~ 'arm/v7' ]]
then
    curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm.deb -o /tmp/cloudflared.deb
    dpkg --add-architecture arm
    echo "$(date "+%d.%m.%Y %T") Added cloudflared for ${TARGETPLATFORM}" >> /build.info
elif [[ ${TARGETPLATFORM} =~ 'arm/v6' ]]
then
    #curl -sL https://hobin.ca/cloudflared/latest?type=deb -o /tmp/cloudflared.deb
    wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm
else 
    echo "$(date "+%d.%m.%Y %T") Unsupported platform - cloudflared not added" >> /build.info
fi
  if [[ ${TARGETPLATFORM} =~ 'arm/v6' ]]
  then
    sudo cp ./cloudflared-linux-arm /usr/local/bin/cloudflared
    sudo chmod +x /usr/local/bin/cloudflared
    cloudflared -v    
  else
    apt install /tmp/cloudflared.deb \
        && rm -f /tmp/cloudflared.deb \
        && useradd -s /usr/sbin/nologin -r -M cloudflared \
        && chown cloudflared:cloudflared /usr/local/bin/cloudflared
  fi

# clean cloudflared config
mkdir -p /etc/cloudflared \
    && rm -f /etc/cloudflared/config.yml

# clean up
apt-get -y autoremove \
    && apt-get -y autoclean \
    && apt-get -y clean \
    && rm -fr /tmp/* /var/tmp/* /var/lib/apt/lists/*

# Creating pihole-dot-doh service
mkdir -p /etc/services.d/pihole-dot-doh

# run file
echo '#!/bin/bash' > /etc/services.d/pihole-dot-doh/run
# Copy config file if not exists
echo 'cp -n /temp/stubby.yml /config/' >> /etc/services.d/pihole-dot-doh/run
echo 'cp -n /temp/cloudflared.yml /config/' >> /etc/services.d/pihole-dot-doh/run
# run stubby in background
echo 's6-echo "Starting stubby"' >> /etc/services.d/pihole-dot-doh/run
echo 'stubby -g -C /config/stubby.yml' >> /etc/services.d/pihole-dot-doh/run
# run cloudflared in foreground
echo 's6-echo "Starting cloudflared"' >> /etc/services.d/pihole-dot-doh/run
echo '/usr/local/bin/cloudflared --config /config/cloudflared.yml' >> /etc/services.d/pihole-dot-doh/run

# finish file
echo '#!/bin/bash' > /etc/services.d/pihole-dot-doh/finish
echo 's6-echo "Stopping stubby"' >> /etc/services.d/pihole-dot-doh/finish
echo 'killall -9 stubby' >> /etc/services.d/pihole-dot-doh/finish
echo 's6-echo "Stopping cloudflared"' >> /etc/services.d/pihole-dot-doh/finish
echo 'killall -9 cloudflared' >> /etc/services.d/pihole-dot-doh/finish

# Make bash scripts executable
chmod -v +x /etc/services.d/pihole-dot-doh/run
chmod -v +x /etc/services.d/pihole-dot-doh/finish


### Lancache cache domains code below
mkdir -p /etc/s6-overlay/s6-rc.d/_cachedomainsonboot
mkdir -p /etc/s6-overlay/s6-rc.d/_cachedomainsonboot/dependencies.d
echo "" > /etc/s6-overlay/s6-rc.d/_cachedomainsonboot/dependencies.d/pihole-FTL
echo "oneshot" > /etc/s6-overlay/s6-rc.d/_cachedomainsonboot/type
echo "#!/command/execlineb
background { bash -e /usr/local/bin/_cachedomainsonboot.sh }" > /etc/s6-overlay/s6-rc.d/_cachedomainsonboot/up

echo "#!/bin/bash
# Grabbing the repo
cd ~
git clone https://github.com/uklans/cache-domains.git

# Making copies of the files
mkdir -p /etc/cache-domains/ && cp \`find ~/cache-domains -name *.txt -o -name cache_domains.json\` /etc/cache-domains
mkdir -p /etc/cache-domains/scripts/ && cp ~/cache-domains/scripts/create-dnsmasq.sh /etc/cache-domains/scripts/


# Setting up our config.json file
mkdir -p /etc/cache-domains/config
cp -n /temp/config.json /etc/cache-domains/config/
if [ -f \"/etc/cache-domains/scripts/config.json\" ]; then
	rm /etc/cache-domains/scripts/config.json
fi

chown -v root:root /etc/cache-domains/config/*
chmod -v 644 /etc/cache-domains/*

ln -s /etc/cache-domains/config/config.json /etc/cache-domains/scripts/config.json 

# Make bash scripts executable
chmod -v +x /etc/cache-domains/scripts/create-dnsmasq.sh

# Manually generating our dnsmasq files
cd /etc/cache-domains/scripts
./create-dnsmasq.sh

# Copying our files for Pi-hole to use 
sudo cp -r /etc/cache-domains/scripts/output/dnsmasq/*.conf /etc/dnsmasq.d/


# Automating the process
cp -n /temp/lancache-dns-updates.sh /usr/local/bin/
chmod -v +x /usr/local/bin/lancache-dns-updates.sh
" >  /usr/local/bin/_cachedomainsonboot.sh
chmod -v +x /usr/local/bin/_cachedomainsonboot.sh

echo "Installed cache-domain files!"

if [ ! -d "/etc/s6-overlay/s6-rc.d/_postFTL" ]; then
    echo "Missing /etc/s6-overlay/s6-rc.d/_postFTL directory"
    exit 1
fi

mkdir -pv /etc/s6-overlay/s6-rc.d/_postFTL/dependencies.d
echo "" > /etc/s6-overlay/s6-rc.d/_postFTL/dependencies.d/_cachedomainsonboot
echo "Added dependency to _postFTL service (/etc/s6-overlay/s6-rc.d/_postFTL/dependencies.d/_cachedomainsonboot)!"

if [ ! -f "/etc/cron.d/cache-domains" ]; then
		echo "# cache-domains Updater by mwatz1234
# https://github.com/mwatz1234/pihole-dot-doh-updatelists-lancache-cache-domains

#30 4 * * *   root   /usr/local/bin/lancache-dns-updates.sh
" > /etc/cron.d/cache-domains
		sed "s/#30 /$((1 + RANDOM % 58)) /" -i /etc/cron.d/cache-domains
		echo "Created crontab (/etc/cron.d/cache-domains)"
	fi        

echo "Created crontab line for cache-domains"
    
