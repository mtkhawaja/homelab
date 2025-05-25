#!/usr/bin/env zsh

  SSH_CONFIG_FILE="/etc/ssh/sshd_config"

if [ ! -f "$SSH_CONFIG_FILE" ]; then
    echo "Error: SSH config file $SSH_CONFIG_FILE not found."
    exit 1
fi

sudo cp "$SSH_CONFIG_FILE" "$HOME/ssh-config-backup-$(date +%Y%m%d%H%M%S)"
sudo sed -i 's/^#*PermitRootLogin\s\+\(yes\|prohibit-password\)/PermitRootLogin no/' "$SSH_CONFIG_FILE"
sudo sed -i 's/^#*PasswordAuthentication\s\+yes/PasswordAuthentication no/' "$SSH_CONFIG_FILE"
systemctl restart ssh
