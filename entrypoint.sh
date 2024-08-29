#!/bin/bash

# Exit when any command fails
set -e

# Create a tun for WARP
echo "Creating tun for WARP..."
sudo mkdir -p /dev/net
echo "Checking if /dev/net/tun exists..."
if [ ! -c /dev/net/tun ]; then
    echo "Creating TUN device..."
    sudo mknod /dev/net/tun c 10 200
    echo "Setting permissions for TUN device..."
    sudo chmod 600 /dev/net/tun
    echo "TUN device created."
else
    echo "TUN device already exists."
fi

# Start dbus service
sudo mkdir -p /run/dbus
echo "Checking if /run/dbus/pid exists..."
if [ -f /run/dbus/pid ]; then
    echo "Removing /run/dbus/pid..."
    sudo rm /run/dbus/pid
fi
echo "Starting dbus service..."
sudo dbus-daemon --config-file=/usr/share/dbus-1/system.conf

# Start the Cloudflare WARP service
echo "Starting WARP service..."
sudo warp-svc --accept-tos &

# Sleep to wait for the WARP service to start
echo "Sleeping for 5 seconds..."
sleep 5

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

# Start the proxy
gost $GOST_ARGS

# Start Docker Daemon in the background
echo "Starting Docker Daemon..."
/usr/local/bin/start-docker.sh &

# Sleep to wait for the Docker Daemon to start
echo "Sleeping for 5 seconds..."
sleep 5

# Run inner Docker container with NetBird client
echo "Installing netbird client..."
docker run -d --name netbird-container --network host \
 --cap-add=NET_ADMIN \
 -e NB_SETUP_KEY="$NETBIRD_SETUP_KEY" \
 -v netbird-client:/etc/netbird \
 -e NB_MANAGEMENT_URL="$NETBIRD_MGMT_URL" \
 netbirdio/netbird:latest

# Execute specified command
"$@"
