## Constants
VERSION="0.0.2"
ARCH="i386"
BASE_DIR=$PWD
COINTU="cointu-$VERSION-$ARCH"
COINTU_ISO="$COINTU.iso"

## Get CLI options
## -s do not verify ISO integrity
while getopts i:t:p: opt; do
  case $opt in
    i)
      ISO=$OPTARG
      ;;
    t)
      TMP=$OPTARG
      ;;
    p)
      PARTITION=$OPTARG
      ;;
  esac
done
shift $((OPTIND - 1))

if [ -z $ISO ] ; then
  echo "Must specify -i parameter"
  exit 1
fi


## Check for dependencies
sh checkDependencies.sh
if [ $? -eq 1 ]; then 
  echo "Dependency check failed."
  exit 1;
fi

## Directory Setup
TMP=".tmp"
SRC="$TMP/src"
LIVE="$TMP/live"
CUSTOM="$TMP/custom"
CD="$TMP/cd"
SQUASHFS=$TMP/squashfs

mkdir -p $SRC $TMP $CD $CUSTOM $SQUASHFS 

## Prepare for customization
echo "Mounting source ISO $ISO to $SRC"
sudo mount -o loop $ISO $SRC
echo "Unpacking ISO into $CD This might take a minute."
rsync --exclude="/casper/filesystem.squashfs" -a $SRC/ $CD
sudo modprobe squashfs
echo "Mounting squashfs"
sudo mount -t squashfs -o loop $SRC/casper/filesystem.squashfs $SQUASHFS
echo "Copying $SQUASHFS contents into $CUSTOM. This might take a minute."
sudo cp -a $SQUASHFS/* $CUSTOM

## Enable guest distro network access
echo "Copying host network access files into guest (these will be deleted later)"
sudo cp /etc/resolv.conf /etc/hosts $CUSTOM/etc

## Customize guest distro 
echo "Preparing for customization of $ISO"
sudo cp -r packages $CUSTOM/tmp
sudo cp guest.sh $CUSTOM/tmp
echo "Running guest customization script."
sudo chroot $CUSTOM /bin/bash /tmp/guest.sh

## Rebuild filesystem manifest
echo "Rebuilding filesystem manifest.."
sudo chmod +w $CD/casper/filesystem.manifest
sudo chroot $CUSTOM dpkg-query -W --showformat='${Package} ${Version}\n' > $CD/casper/filesystem.manifest
sudo cp $CD/casper/filesystem.manifest $CD/casper/filesystem.manifest-desktop

## Regenerate squashfs
echo "Regenerating squashfs.."
sudo rm $CD/casper/filesystem.squashfs
sudo mksquashfs $CUSTOM $CD/casper/filesystem.squashfs -no-progress
echo "Done generating squashfs."
sudo rm -f $CD/md5sum.txt
cd $CD
echo "Regnerating md5sums.."
sudo find . -type f -print0 | xargs -0 md5sum > md5sum.txt
echo "Building iso $COINTU_ISO. This might take a minute."
mkisofs --quiet -D -r -V "$COINTU" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $BASE_DIR/$COINTU_ISO .
echo "Generating sha256 checksum of $COINTU_ISO"
sha256sum $BASE_DIR/$COINTU_ISO > $BASE_DIR/$COINTU.sha256
cd $BASE_DIR
sudo umount $SQUASHFS
sudo umount $SRC
if $PARTITION ; then
  ./usb.sh -i $COINTU_ISO -p $PARTITION
fi
