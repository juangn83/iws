#!/bin/bash
setxkbmap latam
# Find the connected HDMI port name dynamically and enable it
HDMI_PORT=$(xrandr | grep -w "connected" | grep "HDMI" | awk '{print $1}')

if [ -n "$HDMI_PORT" ]; then
    echo "[+] Found HDMI output: $HDMI_PORT. Activating..."
    xrandr --output "$HDMI_PORT" --auto --right-of eDP-1
else
    echo "[-] No connected HDMI output found."
fi
sudo apt install terminator git wget curl
wget https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64
sudo dpkg -i *.deb
