#!/usr/bin/env zsh

#
# Documentation Reference:
# https://ubuntu.com/tutorials/install-and-configure-samba
# [development]
#    comment = Source Code Samba share on Ubuntu
#    path = <unix-path>
#    read only = no
#    browsable = yes
#
#
# Windows
# \\<domain-name>\<unix-path>
#

sudo apt update && sudo apt install samba
mkdir "<unix-path>"
sudo nvim /etc/samba/smb.conf
sudo ufw allow samba
sudo service smbd restart

