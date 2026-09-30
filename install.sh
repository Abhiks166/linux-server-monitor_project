#!/bin/bash

INSTALL_DIR="/opt/linux-server-monitor"

echo "Installing Linux Server Monitor..."

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

sudo systemctl daemon-reload
sudo systemctl enable --now linux-server-monitor.timer

echo "Monitoring timer enabled."

