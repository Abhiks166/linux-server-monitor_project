#!/bin/bash

INSTALL_DIR="/opt/linux-server-monitor"

echo "Installing Linux Server Monitor..."

sudo mkdir -p "$INSTALL_DIR"

echo "Installation directory: $INSTALL_DIR"

sudo cp monitor.sh "$INSTALL_DIR/"
sudo cp -r config "$INSTALL_DIR/"
sudo mkdir -p "$INSTALL_DIR/logs"

echo "Application files copied."
