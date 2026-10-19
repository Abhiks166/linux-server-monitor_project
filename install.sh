#!/bin/bash

INSTALL_DIR="/opt/linux-server-monitor"

echo "Installing Linux Server Monitor..."

# Create dedicated system user if not already present
# if ! id -u linux-monitor >/dev/null 2>&1; then
#    sudo useradd --system --no-create-home --shell /usr/sbin/nologin linux-monitor
# fi


sudo mkdir -p "$INSTALL_DIR"

echo "Installation directory: $INSTALL_DIR"

sudo cp monitor.sh "$INSTALL_DIR/"
sudo cp -r config "$INSTALL_DIR/"
sudo mkdir -p "$INSTALL_DIR/logs"
sudo chown linux-monitor:linux-monitor "$INSTALL_DIR/logs"

sudo mkdir -p "$INSTALL_DIR/state"
sudo chown -R linux-monitor:linux-monitor "$INSTALL_DIR/state"

echo "Application files copied."

sudo cp systemd/linux-server-monitor.service /etc/systemd/system/
sudo cp systemd/linux-server-monitor.timer /etc/systemd/system/

echo "Systemd files installed."

TEMP_CONFIG="/tmp/linux-server-monitor.logrotate.$$"

if sudo install -o root -g root -m 0644 \
    logrotate/linux-server-monitor "$TEMP_CONFIG"; then

    if sudo logrotate --debug "$TEMP_CONFIG"; then
        sudo install -o root -g root -m 0644 \
            logrotate/linux-server-monitor \
            /etc/logrotate.d/linux-server-monitor

        echo "Log rotation configuration installed."
    else
        echo "ERROR: Logrotate configuration validation failed."
        sudo rm -f "$TEMP_CONFIG"
        exit 1
    fi
else
    echo "ERROR: Could not prepare logrotate configuration."
    exit 1
fi

sudo rm -f "$TEMP_CONFIG"

sudo systemctl daemon-reload
sudo systemctl enable --now linux-server-monitor.timer

echo "Monitoring timer enabled."

