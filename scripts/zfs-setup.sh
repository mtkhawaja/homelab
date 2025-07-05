#!/usr/bin/env zsh

#
# Documentation Reference:
# https://ubuntu.com/tutorials/setup-zfs-storage-pool
#

sudo apt install zfsutils-linux
whereis zfs
sudo fdisk -l
sudo zpool create -f <pool-name-1> "space delimited devices go here"
sudo zpool create -f <pool-name-2> "space delimited devices go here"
sudo zpool status

# zpool disappears after reboot
sudo zpool import