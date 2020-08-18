#!/bin/bash

banner() {
  echo "                               __"
  echo " .-----.---.-.----.----.-----.|  |_"
  echo " |  _  |  _  |   _|   _|  _  ||   _|"
  echo " |   __|___._|__| |__| |_____||____|         __"
  echo " |__| .-----.----.-----.-----.-----.-----.--|  |.-----.----."
  echo "      |  _  |   _|  -__|__ --|  -__|  -__|  _  ||  -__|   _|"
  echo "      |   __|__| |_____|_____|_____|_____|_____||_____|__|"
  echo "      |__|                                      (by scott)"
  echo " "
}

usage() {
  banner
  echo "$package - Tool to load a custom preseed configuration into the Parrot ISO."
  echo " "
  echo "Note 0: Changing preseed options can have unintended results that can impact the security or functionality of your Parrot installation. Use this tool at your own risk."
  echo "Note 1: This was built specifically for Parrot OS ISOs, but probably would work with other ISOs."
  echo "Sample usage:"
  echo "Extract:  $package -i Parrot-security-4.9.1_x64.iso -x preseed_orig.cfg"
  echo "Generate: $package -i Parrot-security-4.9.1_x64.iso -p preseed_new.cfg"
  echo " "
  echo "options:"
  echo "-h, --help         show this help dialog"
  echo "-i [PARROT.ISO]    iso file to use"
  echo "-x [FILE]          extract preseed.cfg file and save as [FILE]"
  echo "-p [PRESEED.CFG]   preseed file to load"
  echo " "
}

extract() {
  # Create directories for processing
  mkdir -p /tmp/pps/
  mkdir -p /tmp/pps/mnt
  mkdir -p /tmp/pps/initrdfiles

  # Make sure ISO isn't already mounted
  if grep -qs '/tmp/pps/mnt ' /proc/mounts; then
    umount /tmp/pps/mnt
  fi

  # Mount ISO
  mount -o loop $ISOFILE /tmp/pps/mnt/ 2>/dev/null

  # Copy initrd.gz from mounted ISO
  cp /tmp/pps/mnt/install/initrd.gz /tmp/pps

  # Expand initrd
  zcat /tmp/pps/initrd.gz | sh -c 'cd /tmp/pps/initrdfiles && cpio -i --no-absolute-filenames --quiet'

  # Make sure preseed.cfg exists and copy if it does
  if [ -f '/tmp/pps/initrdfiles/preseed.cfg' ]; then
    cp -i /tmp/pps/initrdfiles/preseed.cfg $EXTRACTFILE
  else
    echo "Could not find preseed.cfg in $ISOFILE"
  fi

  # Cleanup everything
  umount /tmp/pps/mnt
  rm -r /tmp/pps/
}

generate() {
  # Create directories for processing
  mkdir -p /tmp/pps/
  mkdir -p /tmp/pps/mnt
  mkdir -p /tmp/pps/isofiles
  mkdir -p /tmp/pps/initrdfiles

  # Make sure ISO isn't already mounted
  if grep -qs '/tmp/pps/mnt ' /proc/mounts; then
    umount /tmp/pps/mnt
  fi

  # Mount ISO
  mount -o loop $ISOFILE /tmp/pps/mnt/ 2>/dev/null

  # Copy initrd.gz from mounted ISO
  cp /tmp/pps/mnt/install/initrd.gz /tmp/pps

  # Expand initrd and copy user's preseed.cfg file to it
  zcat /tmp/pps/initrd.gz | sh -c 'cd /tmp/pps/initrdfiles && cpio -i --no-absolute-filenames --quiet'
  rm /tmp/pps/initrd.gz
  cp $PRESEEDFILE /tmp/pps/initrdfiles/preseed.cfg

  # Pack up new initrd file
  sh -c "cd /tmp/pps/initrdfiles && find . | cpio --create --format='newc' --quiet > /tmp/pps/initrd"
  gzip /tmp/pps/initrd

  # Copy files from mounted ISO
  cp  -rT /tmp/pps/mnt/ /tmp/pps/isofiles
  mv /tmp/pps/initrd.gz /tmp/pps/isofiles/install/

  # Regenerate md5sum.txt
  sh -c 'cd /tmp/pps/isofiles && chmod +w md5sum.txt && find -follow -type f ! -name md5sum.txt -print0 2>/dev/null | xargs -0 md5sum > md5sum.txt && chmod -w md5sum.txt'

  # Generate new ISO file
  sh -c 'cd /tmp/pps/ && sudo genisoimage -quiet -r -J -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o preseeded.iso isofiles'
  mv -i /tmp/pps/preseeded.iso $ISOFILE_DIR/preseed-$ISOFILE_FILE

  # Cleanup everything
  umount /tmp/pps/mnt
  rm -r /tmp/pps/
}

# Make sure script is being run with root privileges
if [ `whoami` != root ]; then
  echo "Please run this script as root or using sudo. Exiting..."
  exit
fi

# Perform a few housekeeping tasks
package=`basename "$0"`
unset ISOFILE EXTRACTFILE PRESEEDFILE ISOFILE_FILE ISOFILE_DIR

# Check if user-supplied command line options are valid
if [ $# -eq 0 ];
then
    usage
    exit
else
  while getopts ":hi:x:p:" opt; do
    case ${opt} in
      h)
        usage
        exit
        ;;
      i)
        ISOFILE=$OPTARG
        ;;
      x)
        EXTRACTFILE=$OPTARG
        ;;
      p)
        PRESEEDFILE=$OPTARG
        ;;
      \?)
        banner
        echo "Invalid option: \"-$OPTARG\"" 1>&2
        echo " "
        exit
        ;;
      :)
        banner
        echo "Invalid option: \"-$OPTARG\" requires an argument" 1>&2
        echo " "
        exit
        ;;
    esac
  done
fi

# Throw in a banner, just for the sake of vanity
banner

# Check if ISO file was specified
if [ -z "$ISOFILE" ]; then
  echo "No ISO file was specified. Exiting..."
  echo " "
  exit
fi

# Check if ISO file exists
if [ ! -f "$ISOFILE" ]; then
  echo "$ISOFILE doesn't exist. Exiting..."
  echo " "
  exit
fi

ISOFILE_DIR=$(dirname "$ISOFILE")
ISOFILE_FILE=$(basename "$ISOFILE")

# Make sure either EXTRACTFILE or PRESEED file has been specified, but not both
if [ -n "$EXTRACTFILE" ] && [ -n "$PRESEEDFILE" ]; then
  echo "You can use either the (-x) option or the (-p) option, but not both at the same time. Exiting..."
  echo " "
  exit
elif [ -z "$EXTRACTFILE" ] && [ -z "$PRESEEDFILE" ]; then
  echo "You must specifiy either the (-x) option or the (-p) option. Exiting..."
  echo " "
  exit
elif [ -n "$EXTRACTFILE" ] && [ -z "$PRESEEDFILE" ]; then
  echo "Extracting preseed.cfg from $ISOFILE and saving as $EXTRACTFILE"
  extract
  echo " "
elif [ -z "$EXTRACTFILE" ] && [ -n "$PRESEEDFILE" ]; then
  if ! command -v genisoimage &> /dev/null; then
    echo "This program requires genisoimage (sudo apt install genisoimage). Exiting..."
    echo " "
    exit
  else
    echo "Generating $ISOFILE_DIR/preseeded_$ISOFILE using $PRESEEDFILE as preseed.cfg"
    generate
    echo " "
  fi
fi
