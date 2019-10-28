#!/bin/bash
#
# More information available at:
# https://jamesachambers.com/raspberry-pi-4-ubuntu-server-desktop-18-04-3-image-unofficial/
# https://github.com/TheRemote/Ubuntu-Server-raspi4-unofficial

# Add updated mesa repository for video driver support
sudo add-apt-repository ppa:ubuntu-x-swat/updates -yn

# Add Raspberry Pi Userland repository
sudo add-apt-repository ppa:ubuntu-raspi2/ppa -yn

# Install dependencies
sudo apt install wireless-tools iw rfkill bluez libraspberrypi-bin haveged libnewt0.52 whiptail parted triggerhappy lua5.1 alsa-utils build-essential git bc bison flex libssl-dev -y

echo "Checking for updates ..."

if [ -d ".updates" ]; then
    cd .updates
    if [ -d "Ubuntu-Server-raspi4-unofficial" ]; then
        cd Ubuntu-Server-raspi4-unofficial
        git fetch --all
        git reset --hard origin/master
        cd ..
    else
        git clone https://github.com/TheRemote/Ubuntu-Server-raspi4-unofficial.git
    fi
else
    mkdir .updates
    cd .updates
    git clone https://github.com/TheRemote/Ubuntu-Server-raspi4-unofficial.git
fi
cd ..

# Check if Updater.sh has been updated
UpdatesHashOld=$(sha1sum "Updater.sh" | cut -d" " -f1 | xargs)
UpdatesHashNew=$(sha1sum ".updates/Ubuntu-Server-raspi4-unofficial/Updater.sh" | cut -d" " -f1 | xargs)

echo "$UpdatesHashOld - $UpdatesHashNew"

if [ "$UpdatesHashOld" != "$UpdatesHashNew" ]; then
    echo "Updater has update available.  Updating now ..."
    rm -f Updater.sh
    cp -f .updates/Ubuntu-Server-raspi4-unofficial/Updater.sh Updater.sh
    chmod +x Updater.sh
    exec $(readlink -f "Updater.sh")
    exit
fi

echo "Updater is up to date.  Checking system ..."

# Find currently installed and latest release
cd .updates
LatestRelease=$(cat "Ubuntu-Server-raspi4-unofficial/BuildPiKernel64bit.sh" | grep "IMAGE_VERSION=" | cut -d"=" -f2 | xargs)
CurrentRelease="0"

if [ -e "/etc/imagerelease" ]; then
    read -r CurrentRelease < "/etc/imagerelease"
fi

if [ "$LatestRelease" == "$CurrentRelease" ]; then
    echo "No updates are currently available!"
    exit
fi

echo "Release v${LatestRelease} is available!  Make sure you have made a full backup."
echo "Note: your /boot cmdline.txt and config.txt files will be reset to the newest version.  Make a backup of those first!"
echo -n "Update now? (y/n)"
read answer
if [ "$answer" == "${answer#[Yy]}" ]; then
    echo "Update has been aborted"
    exit
fi

echo "Downloading update package ..."
if [ -e "updates.tar.xz" ]; then rm -f "updates.tar.xz"; fi
curl --location "https://github.com/TheRemote/Ubuntu-Server-raspi4-unofficial/releases/download/v${LatestRelease}/updates.tar.xz" --output "updates.tar.xz"
if [ ! -e "updates.tar.xz" ]; then
    echo "Update has failed to download -- please try again later"
    exit
fi

# Download was successful, extract and copy updates
echo "Extracting update package - This can take several minutes on the Pi ..."
tar -xf "updates.tar.xz"
rm -f "updates.tar.xz"

if [[ -d "updates" && -d "updates/rootfs" && -d "updates/bootfs" ]]; then
    echo "Copying updates to rootfs ..."
    sudo cp --verbose --archive --no-preserve=ownership updates/rootfs/* /

    echo "Copying updates to bootfs ..."
    sudo cp --verbose --archive --no-preserve=ownership updates/bootfs/* /boot/firmware

    # Update initramfs so our new kernel and modules are picked up
    echo "Updating kernel and modules ..."
    sudo update-initramfs -u

    # Save our new updated release to .lastupdate file
    echo "$LatestRelease" | sudo tee -a /etc/imgrelease >/dev/null;
else
    echo "Update has failed to extract.  Please try again later!"
    exit
fi

# % Fix /lib/firmware symlink
ln -s /lib/firmware /etc/firmware

# % Fix WiFi
# % The Pi 4 version returns boardflags3=0x44200100
# % The Pi 3 version returns boardflags3=0x48200100cd
sudo sed -i "s:0x48200100:0x44200100:g" /mnt/lib/firmware/brcm/brcmfmac43455-sdio.txt

# % Disable ib_iser iSCSI cloud module to prevent an error during systemd-modules-load at boot
sudo sed -i "s/ib_iser/#ib_iser/g" /mnt/lib/modules-load.d/open-iscsi.conf
sudo sed -i "s/iscsi_tcp/#iscsi_tcp/g" /mnt/lib/modules-load.d/open-iscsi.conf

# % Fix update-initramfs mdadm.conf warning
sudo grep "ARRAY devices" /mnt/etc/mdadm/mdadm.conf >/dev/null || echo "ARRAY devices=/dev/sda" | sudo tee -a /mnt/etc/mdadm/mdadm.conf >/dev/null;

# Startup tweaks to fix bluetooth and sound issues
sudo touch /etc/rc.local
cat << EOF | sudo tee /etc/rc.local
#!/bin/bash
#
# rc.local
#

# % Fix crackling sound
if [ -n "`which pulseaudio`" ]; then
  GrepCheck=$(cat /etc/pulse/default.pa | grep "load-module module-udev-detect tsched=0")
  if [ ! -n "$GrepCheck" ]; then
    sed -i "s:load-module module-udev-detect:load-module module-udev-detect tsched=0:g" /etc/pulse/default.pa
  fi
fi

# Enable bluetooth
if [ -n "`which hciattach`" ]; then
  echo "Attaching Bluetooth controller ..."
  hciattach /dev/ttyAMA0 bcm43xx 921600
fi

exit 0
EOF
sudo chmod +x /etc/rc.local

echo "Update completed!  Please reboot your system."
