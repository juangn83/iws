#!/usr/bin/env bash

# Exit immediately if any command fails
set -e

# --- CONFIGURATION ---
# Automatically find a .iso file in the current directory
ISO_FILE=$(ls *.iso 2>/dev/null | head -n 1)

if [ -z "$ISO_FILE" ]; then
    echo "[-] Error: No Debian Live .iso file found in the current directory."
    exit 1
fi

echo "[+] Found ISO image: $ISO_FILE"

# Prompt user for target USB drive (e.g., sdb, sdc)
echo "------------------------------------------------------------------"
lsblk -d -o NAME,SIZE,MODEL,TRAN | grep -E "usb|disk"
echo "------------------------------------------------------------------"
read -p "Enter the target USB drive name ONLY (e.g., sdb, sdc): " USB_NAME

USB_DEV="/dev/${USB_NAME}"

# Safety checks
if [ ! -b "$USB_DEV" ]; then
    echo "[-] Error: $USB_DEV is not a valid block device."
    exit 1
fi

echo "[!] WARNING: All data on $USB_DEV will be completely erased!"
read -p "Are you sure you want to continue? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

# 1. Unmount any active partitions from the target drive
echo "[+] Unmounting any active partitions on $USB_DEV..."
sudo umount ${USB_DEV}* 2>/dev/null || true

# 2. Flash the ISO using dd
echo "[+] Flashing $ISO_FILE to $USB_DEV using dd (this may take a moment)..."
sudo dd if="$ISO_FILE" of="$USB_DEV" bs=4M status=progress conv=fsync

# 3. Inform the kernel of partition table changes and settle
echo "[+] Updating partition table..."
sudo partprobe "$USB_DEV"
sync
sleep 3

# 4. Precisely calculate free space using parted machine-readable output
echo "[+] Calculating available free space for persistence partition..."
FREE_LINE=$(sudo parted -sm "$USB_DEV" unit s print free | grep 'free;' | tail -n 1)

if [ -z "$FREE_LINE" ]; then
    echo "[-] Error: No unallocated free space found on $USB_DEV."
    exit 1
fi

# Extract exact start and end sectors of the free space block
FREE_START=$(echo "$FREE_LINE" | awk -F';' '{print $2}')
FREE_END=$(echo "$FREE_LINE" | awk -F';' '{print $3}')

echo "[+] Creating persistence partition from sector $FREE_START to $FREE_END..."
sudo parted --script "$USB_DEV" mkpart primary ext4 "$FREE_START" "$FREE_END"

# Force kernel to reload the partition table again
sudo partprobe "$USB_DEV"
sync
sleep 3

# 5. Dynamically detect the newly created partition name (handles sdb3, nvme0n1p3, etc.)
PERSIST_PART_NAME=$(lsblk -ln -o NAME "$USB_DEV" | grep -v "^$(basename $USB_DEV)$" | tail -n 1)
PERSIST_PART="/dev/${PERSIST_PART_NAME}"

if [ ! -b "$PERSIST_PART" ]; then
    echo "[-] Error: Could not automatically detect the new persistence partition."
    exit 1
fi

echo "[+] Target persistence partition identified as: $PERSIST_PART"

# 6. Format the partition as ext4 with the required 'persistence' label
echo "[+] Formatting $PERSIST_PART as ext4 with label 'persistence'..."
sudo mkfs.ext4 -F -L "persistence" "$PERSIST_PART"

# 7. Configure the persistence rules
TEMP_DIR=$(mktemp -d)
echo "[+] Mounting $PERSIST_PART to configure persistence.conf..."
sudo mount "$PERSIST_PART" "$TEMP_DIR"

# Write the union overlay rule so all system and home modifications are saved
echo "/ union" | sudo tee "$TEMP_DIR/persistence.conf" > /dev/null

# Cleanup mount
sync
sudo umount "$TEMP_DIR"
rmdir "$TEMP_DIR"

echo "------------------------------------------------------------------"
echo "[+] SUCCESS! Debian Live USB with persistence is ready."
echo "[+] IMPORTANT BOOT INSTRUCTION:"
echo "    When booting from this USB, ensure your boot entry includes"
echo "    the 'persistence' boot parameter (e.g., press 'E' at the GRUB menu"
echo "    and verify 'persistence' is on the linux kernel line)."
echo "------------------------------------------------------------------"