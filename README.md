# NixOS
NixOS config for servers in the field.

1. [Installing NixOS from scratch](#method-1-installing-nixos-from-scratch)
2. [Converting an existing Linux system into NixOS](#method-2-converting-an-existing-linux-system-into-nixos)
3. [Creating an encrypted data partition](#creating-an-encrypted-data-partition)
4. [Secure erasure of SSD drive](#secure-erasure-of-ssd-drive)

## Method 1: Installing NixOS from scratch

### Setting up filesystems

[(LVM reference.)](https://www.digitalocean.com/community/tutorials/an-introduction-to-lvm-concepts-terminology-and-operations)

Use `fdisk` to create partitions, you can list all devices with `fdisk -l` and then run `fdisk <device>` to configure a particular drive.

1. boot partition 1 GB, type 83 (Linux);
2. LVM partition for the rest of the drive, type 8e (Linux LVM);
3. Full drive LVM partition for any extra drives.

(Use the `m` function to see the commands. Use `n` to create a new partition and choose `+1G` for the size for `boot` and the default option of "rest of the disk" for the root partition. Then use `t` to change the type of the root partition and `w` to write the changes.)

Create a physical volume for every LVM partition using
```
pvcreate <partition>
```
Create a volume group containing all volumes using
```
vgcreate LVMVolGroup <partition 1> ... <partition n>
```

**If you plan to create an encrypted data partition**, then create a single 40GB root partition on the LVM volume using
```
lvcreate -L 40GB -n nixos_root LVMVolGroup
```

**If you do not plan to create an encrypted data partition** and want the root filesystem to use the whole disk instead, then use
```
lvcreate -l 100%FREE -n nixos_root LVMVolGroup
```

Create filesystems:
```
mkfs.ext4 -L nixos_boot /dev/<boot partition>
mkfs.ext4 -L nixos_root /dev/LVMVolGroup/nixos_root
```

### Installing the OS

[(NixOS installation manual)](https://nixos.org/nixos/manual/index.html#sec-installation)

```
mount /dev/disk/by-label/nixos_root /mnt
mkdir /mnt/boot
mount /dev/disk/by-label/nixos_boot /mnt/boot
nixos-generate-config --root /mnt
curl -L https://github.com/MSF-OCB/NixOS/archive/master.zip --output /tmp/config.zip
cd /tmp
unzip config.zip
mv NixOS-master/* /mnt/etc/nixos
mv NixOS-master/.gitignore /mnt/etc/nixos
rmdir NixOS-master # Verify it's empty now
cp /mnt/etc/nixos/settings.nix.template /mnt/etc/nixos/settings.nix
```

To find a stable device name for grub and append it to the settings file for copy/paste:
```
ls -l /dev/disk/by-id/ | grep "wwn.*<device>$" | tee -a /mnt/etc/nixos/settings.nix
```
Then you can add the path to the `grub.device` setting.

Set the required settings:
```
nano /mnt/etc/nixos/settings.nix
```

And if you enabled the reverse tunnel service, generate a key pair for the tunnel:
```
ssh-keygen -a 100 -t ed25519 -N "" -C "tunnel@${HOSTNAME}" -f /mnt/etc/nixos/local/id_tunnel
```
if the reverse tunnel service is enabled in settings.nix but the private key is not present, the build will fail and complain that the file cannot be found.

Then launch the installer:
```
nixos-install --no-root-passwd --max-jobs 4
```
*Note down the current IP address*, this will allow you to connect via ssh in a bit, use `ip addr` to find the current address.

Then, reboot, remove the usb drive and boot into the new OS.

### Final steps after booting the OS

You should now be able to connect to the newly installed system with ssh, using the local IP address which you noted down before the reboot.

First check that we are on the correct nix channel
```
sudo nix-channel --list
```
This should show the 18.09 channel with name `nixos`, otherwise we need to add it
```
sudo nix-channel --add https://nixos.org/channels/nixos-18.09 nixos
```

Then we will do a full system update
```
sudo nixos-rebuild switch --upgrade
```

If you just upgraded from an existing Linux system, it's safer to reinstall the bootloader once more to avoid issues
```
sudo nixos-rebuild switch --upgrade --install-bootloader
```

Next, if not already done, we'll put the content of the *public* key file for the reverse tunnel (`/etc/nixos/local/id_tunnel.pub`) in the `authorized_keys` file for the tunnel user on github (this repo, `keys/tunnel`). (Easiest way is to connect via SSH on the local network to copy the key.)
Then do a `git pull` and a rebuild of the config on the ssh relay servers.

Finally, we will turn `/etc/nixos` into a git clone of this repository
```
git init
git remote add origin https://github.com/MSF-OCB/NixOS
git fetch
git checkout --force --track origin/master  # Force to overwrite local files
git pull --rebase
```
Check with `git status` that there are no left-over untracked files, these should probably be either deleted or commited.

You're all done! Refer to [Creating an encrypted data partition](#creating-an-encrypted-data-partition) if you want to set up an encrypted data partition.

---

## Method 2: Converting an existing Linux system into NixOS

We don't need a swap partition since we use zram swap on NixOS, we'll thus delete the swap partition and add the extra space to the root partition.

Usually the swap device is in the LVM partition, use `lvdisplay` to identify it (and note down the root partition too), then run

```
sudo swapoff <swap device>
sudo lvremove <swap device>
sudo lvextend -l +100%FREE <root device>
sudo resize2fs <root device>
```
Set labels for the partitions
```
sudo e2label <root device> nixos_root
sudo e2label <boot device> nixos_boot
```
We'll also convert the boot partition from ext2 to ext4 (if needed)
```
sudo umount /boot/
sudo tune2fs -O extents,uninit_bg,dir_index,has_journal /dev/disk/by-label/nixos_boot
sudo fsck.ext4 -vf /dev/disk/by-label/nixos_boot
```

Change the filesystem type in `/etc/fstab` and remount with `mount -a`.

Then we'll follow the steps from [here](https://nixos.org/nixos/manual/index.html#sec-installing-from-other-distro):

```
bash <(curl -C - https://nixos.org/nix/install)
. $HOME/.nix-profile/etc/profile.d/nix.sh
nix-channel --add https://nixos.org/channels/nixos-18.09 nixpkgs
nix-channel --update
nix-env -iE "_: with import <nixpkgs/nixos> { configuration = {}; }; with config.system.build; [ nixos-generate-config nixos-install nixos-enter manual.manpages ]"
sudo `which nixos-generate-config` --root /
```

Edit `/etc/nixos/hardware-configuration.nix` and make sure that no swap device is mentionned and remove any spurious partitions left over from the previous Linux version (like `/var/lib/lxcfs`).

Next, run the steps to download the NixOS config from [this section](#installing-the-os) (but do not run the installer as instructed there!!) and put the config in `/etc/nixos`. Note that we are not mounting the filesystem under `/mnt/` here but working directly in `/etc/`. This is also the time to make any modifications to the config before we build it.

Then we'll go ahead and built the final NixOS system and setup the necessary files to have the conversion done on the next boot.
```
nix-env -p /nix/var/nix/profiles/system -f '<nixpkgs/nixos>' -I nixos-config=/etc/nixos/configuration.nix -iA system
sudo chown -R 0.0 /nix/
sudo chmod 1777 /nix/var/nix/profiles/per-user/
sudo chmod 1777 /nix/var/nix/gcroots/per-user/
sudo touch /etc/NIXOS
echo etc/nixos | sudo tee -a /etc/NIXOS_LUSTRATE
sudo mkdir /boot_old
sudo mv -v /boot/* /boot_old/
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot
```
*Note down the current IP address*, this will allow you to connect via ssh in a bit, use `ip addr` to find the current address.

*!!Very important!!*
If you are converting a system to which you do not have direct ssh access and which can only be accessed via a tunnel, you need to make sure that the tunnel service will work after the reboot!

To do so, make sure that the private key to log on to the ssh relay is already present at `/etc/nixos/local/id_tunnel` at this point and that the corresponding public key is enabled on the relay servers.
*!!Verify this very carefully, otherwise you will lock yourself out of the system!!*

Reboot and you should end up in a NixOS system! The old contents of the root directory can be found at `/old_root/`.

Now follow [the final steps of the general installation guide](#final-steps-after-booting-the-os).

## Creating an encrypted data partition

To encrypt the data on the server, we have two options. Either, and this is the preferred method, we anticipated this from the start and we left sufficient room to create a data partition. Alternatively, we can create a file to hold the encrypted partition.

To create the data partition, using up the remaining space in the volume group, do
```
sudo lvcreate -l 100%FREE -n nixos_data LVMVolGroup
```
If instead you want to create a file `/safe.img` to hold the encrypted partition, you can create it with (use an appropriate size according to the available disk space, for a 128GB drive, we usually allocate 70-80 GB for data)
```
sudo fallocate -l 70G /safe.img
```

From this point forward, all commands are the same for the two methods, but in a couple of places, where we reference the underlying encrypted device, you need to put in the right device, this means either `/dev/LVMVolGroup/nixos_data`, when using a physical partition, or `/safe.img`, when using a file container. We will use the placehold `<device>` where needed, which is to be replaced by the correct value.

Create the encrypted LUKS volume on top of this, use a *strong* passphrase, preferably 128 characters and randomly generated by a password manager. Make sure to store this passphrase securely in the password manager!
```
sudo cryptsetup -v --cipher aes-xts-plain64 --key-size 512 --hash sha512 --use-random luksFormat --type luks2 <device>
```

If you get a message that there is not enough entropy in the system to generate the key, you can open a second shell on the same machine and run `ls -R /` to generate entropy.

Next, we open the volume and create a filesystem on it
```
sudo cryptsetup open <device> nixos_data_decrypted
sudo mkfs.ext4 -L nixos_data /dev/mapper/nixos_data_decrypted
sudo tune2fs -m 0 /dev/disk/by-label/nixos_data
```

We will mount the encrypted filesystem on `/opt`
```
sudo mkdir /opt
sudo mount /dev/disk/by-label/nixos_data /opt
```

Next we will bind mount `/var/lib/docker` into the encrypted volume on `/opt/docker`. If docker is already installed, run these commands first:
```
sudo systemctl stop docker.socket
sudo systemctl stop docker.service
sudo mkdir /opt/docker
```
Open a root shell with `sudo -s` and run
```
mv /var/lib/docker/* /opt/docker/
```
And `Ctrl-d` out of the root shell.

Otherwise or after this, we can create the mount
```
sudo mkdir /var/lib/docker # In case the dir does not exist yet
sudo mount --bind /opt/docker/ /var/lib/docker
```

Finally, we will add a keyfile to be able to unlock the encrypted volume automatically on boot
```
sudo dd bs=512 count=4 if=/dev/urandom of=/keyfile
sudo chown root:root /keyfile
sudo chmod 0600 /keyfile

sudo cryptsetup luksAddKey <device> /keyfile
```

Now enable `crypto.nix` in `settings.nix` and set the setting `crypto.encryptedDevice` to either `/dev/LVMVolGroup/nixos_data` or `/safe.img`, depending on what method you used, to have automounting at boot time and reboot to test.

To quickly disable a key file, run (**do not run this as part of the installation**)
```
sudo cryptsetup luksRemoveKey <device> /keyfile
```

## Secure erasure of SSD drive
After having disabled the key for the encrypted partition, it is recommended to perform a **secure erase** of the whole drive. Afterwards the device can be refurbished by installing a new OS from scratch.

We start by installing some required tools:
```
sudo nix-env -iA nixos.hdparm nixos.pmutils
```

Next, we check whether our drive is in the "frozen" state by running
```
sudo hdparm -I /dev/sdX
```
Check for the output at the end, if there is no `not` in front of `frozen` and the output looks something like this:
```
Security:
        Master password revision code = 65534
                supported
        not     enabled
        not     locked
                frozen
        not     expired: security count
                supported: enhanced erase
```
then we have to unfreeze the drive. The most reliable method seems to be to suspend the device, and then ask someone with physical access to unsuspend the device again. Suspending can be done with
```
sudo pm-suspend
```

After this, the drive should be unfrozen and we can continue with the two commands to erase the drive:
```
sudo hdparm --user-master u --security-set-pass password /dev/sdX
sudo hdparm --user-master u --security-erase-enhanced password /dev/sdX
```

After doing this, the system will still be running but the disk has been erased. After a reboot, the BIOS will report that no OS has been found and you can install a new OS from a flash drive.

If you are no longer able to do a reboot or shutdown (because not all that's required is loaded in memory), you can force a shutdown with
```
echo 1 > /proc/sys/kernel/sysrq 
echo o > /proc/sysrq-trigger
```
