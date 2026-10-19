#!/bin/bash
set -e
trap 'echo "ERROR: Installation failed near line $LINENO." >&2' ERR


INSTALL_DIR="/opt/linux-server-monitor"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check required commands
for cmd in sudo cp install logrotate systemctl id visudo; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: $cmd" >&2
        exit 2
    fi
done

# Check required project files
for file in monitor.sh config/monitor.conf \
            systemd/linux-server-monitor.service \
            systemd/linux-server-monitor.timer \
            logrotate/linux-server-monitor; do
    if [ ! -f "$SCRIPT_DIR/$file" ]; then
        echo "ERROR: Required file not found: $SCRIPT_DIR/$file" >&2
        exit 1
    fi
done

# Check required system user
if ! id -u linux-monitor >/dev/null 2>&1; then
    echo "ERROR: Required user 'linux-monitor' does not exist." >&2
    echo "Create the user before running this installer." >&2
    exit 1
fi

# Check required sudoers configuration
SUDOERS_FILE="/etc/sudoers.d/linux-monitor"

if [ ! -f "$SUDOERS_FILE" ]; then
    echo "ERROR: Required sudoers file not found: $SUDOERS_FILE" >&2
    echo "Configure restricted recovery permissions before installing." >&2
    exit 1
fi

if ! sudo visudo -cf "$SUDOERS_FILE" >/dev/null; then
    echo "ERROR: Sudoers configuration is invalid." >&2
    exit 1
fi

echo "Installing Linux Server Monitor..."

#How to create dedicated system user if not already present
# if ! id -u linux-monitor >/dev/null 2>&1; then
#    sudo useradd --system --no-create-home --shell /usr/sbin/nologin linux-monitor
# fi


sudo mkdir -p "$INSTALL_DIR"

echo "Installation directory: $INSTALL_DIR"

sudo cp "$SCRIPT_DIR/monitor.sh" "$INSTALL_DIR/"
sudo cp -r "$SCRIPT_DIR/config" "$INSTALL_DIR/"
sudo mkdir -p "$INSTALL_DIR/logs"
sudo chown linux-monitor:linux-monitor "$INSTALL_DIR/logs"

sudo mkdir -p "$INSTALL_DIR/state"
sudo chown -R linux-monitor:linux-monitor "$INSTALL_DIR/state"

echo "Application files copied."

sudo cp "$SCRIPT_DIR/systemd/linux-server-monitor.service" /etc/systemd/system/
sudo cp "$SCRIPT_DIR/systemd/linux-server-monitor.timer" /etc/systemd/system/

echo "Systemd files installed."

TEMP_CONFIG="/tmp/linux-server-monitor.logrotate.$$"

if sudo install -o root -g root -m 0644 \
    "$SCRIPT_DIR/logrotate/linux-server-monitor" "$TEMP_CONFIG"; then

    if sudo logrotate --debug "$TEMP_CONFIG"; then
        sudo install -o root -g root -m 0644 \
            "$SCRIPT_DIR/logrotate/linux-server-monitor" \
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

