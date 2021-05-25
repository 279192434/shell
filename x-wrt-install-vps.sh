#!/bin/sh

BDEV=sda
#static ip
#network=10.0.4.7,255.255.252.0,10.0.7.255,8.8.8.8
#static ip swap eth0 eth1
#network="117.18.13.159,255.255.255.0,117.18.13.1,8.8.8.8,initscript=dWNpIHNldCBuZXR3b3JrLmxhbi5pZm5hbWU9ZXRoMQp1Y2kgc2V0IG5ldHdvcmsud2FuLmlmbmFtZT1ldGgwCnVjaSBjb21taXQgbmV0d29yawo="
#dhcp ip
#network=dhcp

vmroot=/tmp/block
mkdir -p $vmroot
mount /dev/${BDEV}1 $vmroot || exit 0
cp $vmroot/x-wrt.img.gz /tmp/x-wrt.img.gz && {
	cd /
	umount $vmroot
	sync
	(zcat /tmp/x-wrt.img.gz;
	) >/dev/$BDEV && reboot
}
