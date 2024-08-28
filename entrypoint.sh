#!/bin/bash

# Exit when any command fails
set -e

# Create a tun  for WARP
sudo mkdir -p /dev/net
sudo mknod /dev/net/tun c 10 200
sudo chmod 600 /dev/net/tun

# Start dbus service
sudo mkdir -p /run/dbus
if [ -f /run/dbus/pid ]; then
    sudo rm /run/dbus/pid
fi
sudo dbus-daemon --config-file=/usr/share/dbus-1/system.conf

# Start the Cloudflare WARP service
sudo warp-svc --accept-tos &

# Sleep to wait for the WARP service to start
sleep "$WARP_SLEEP"

# Check if WARP client is registered
if [ ! -f /var/lib/cloudflare-warp/reg.json ]; then
    if [ ! -f /var/lib/cloudflare-warp/mdm.xml ]; then
        warp-cli registration new && echo "Warp client registered!"
        # if a license key is provided, register the license
        if [ -n "$WARP_LICENSE_KEY" ]; then
            echo "License key found, registering license..."
            warp-cli registration license "$WARP_LICENSE_KEY" && echo "Warp license registered!"
        fi
    fi
    # connect to the warp server
    warp-cli --accept-tos connect
else
    echo "Warp client already registered, skip registration"
fi

# Start Docker service
sudo service docker start

# Wait for Docker to start
sleep 2

# Run inner Docker container with NetBird
docker run -d --name netbird-container --network host \
 --cap-add=NET_ADMIN \
 -e NB_SETUP_KEY="$NETBIRD_SETUP_KEY" \
 -v netbird-client:/etc/netbird \
 -e NB_MANAGEMENT_URL="$NETBIRD_MGNT_URL" \
 netbirdio/netbird:latest

# Start the proxy
gost $GOST_ARGS
