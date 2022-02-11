define mount_rootfs
	mkdir tmp.mnt
	sudo mount -t ext4 -o loop $(1) tmp.mnt/
endef

define mount_binds
	sudo mount -t proc /proc tmp.mnt/proc/
	sudo mount --make-rslave --rbind /sys tmp.mnt/sys/
	sudo mount --make-rslave --rbind /dev tmp.mnt/dev/
endef

define unmount_binds
	sudo umount -R tmp.mnt/dev/
	sudo umount -R tmp.mnt/sys/
	sudo umount tmp.mnt/proc/
endef

define unmount_rootfs
	sudo umount tmp.mnt/
	rmdir tmp.mnt
endef

debian_armhf.tar.gz:
	sudo debootstrap --arch=armhf --components main,contrib,non-free sid tmp.debian_armhf/ http://apt-cache:3142/debian/
	echo "root:root" | sudo chroot tmp.debian_armhf/ chpasswd
	sudo tar czf $@ -C tmp.debian_armhf/ .
	sudo rm -r tmp.debian_armhf/

debian_armhf.disk: debian_armhf.tar.gz
	dd if=/dev/zero of=tmp.$@ bs=1M count=8096
	sudo mkfs.ext4 -F tmp.$@

	$(call mount_rootfs,tmp.$@)
	sudo tar xvf $< -C tmp.mnt/
	$(call mount_binds)

	sudo chroot tmp.mnt/ sh -c "cat /etc/apt/sources.list | sed s/deb/deb-src/ >> /etc/apt/sources.list"
	sudo chroot tmp.mnt/ apt-get -y update
	sudo chroot tmp.mnt/ apt-get -y install build-essential git meson valgrind gdb autoconf libtool pkg-config devscripts locales-all linux-image-armmp-lpae
	sudo chroot tmp.mnt/ apt-get -y clean

	$(call unmount_binds)
	$(call unmount_rootfs)

	mv tmp.$@ $@

debian_directfb_armhf.disk: debian_armhf.disk
	cp $<  tmp.$@
	$(call mount_rootfs,tmp.$@)
	$(call mount_binds)
	sudo chroot tmp.mnt/ apt-get -y update

	# rebuild libdrm to get libkms
	sudo chroot tmp.mnt/ apt-get -y install libdrm-dev
	sudo chroot tmp.mnt/ apt-get -y build-dep libdrm-dev
	sudo chroot tmp.mnt/ sh -c "mkdir /root/libdrm/ && cd /root/libdrm/ && apt-get -y source libdrm-dev"
	sudo cp libdrm.patch tmp.mnt/root/libdrm/
	sudo chroot tmp.mnt/ sh -c "cd /root/libdrm/libdrm-2.4.109 && patch -p1 < ../libdrm.patch && debuild -us -uc && dpkg -i ../*.deb"

	sudo chroot tmp.mnt/ sh -c "cd /root && git clone https://github.com/deniskropp/flux.git"
	sudo chroot tmp.mnt/ sh -c "cd /root/flux && autoreconf -fi && ./configure && make && make install"

	sudo chroot tmp.mnt/ sh -c "cd /root && git clone https://github.com/directfb2/DirectFB2.git"
	sudo chroot tmp.mnt/ sh -c "cd /root/DirectFB2 && meson build && cd build && ninja && ninja install"

	sudo chroot tmp.mnt/ sh -c "cd /root && git clone https://github.com/directfb2/DirectFB-examples.git"
	sudo chroot tmp.mnt/ sh -c "cd /root/DirectFB-examples && meson build && cd build && ninja && ninja install"

	$(call unmount_binds)
	$(call unmount_rootfs)
	mv tmp.$@ $@

mount_directfb_armhf: debian_directfb_armhf.disk
	$(call mount_rootfs,$<)
	$(call mount_binds)

umount:
	$(call unmount_binds)
	$(call unmount_rootfs)

chroot_debian_armhf: debian_directfb_armhf.disk
	$(call mount_rootfs,$<)
	$(call mount_binds)
	- sudo chroot tmp.mnt/ /bin/bash
	$(call unmount_binds)
	$(call unmount_rootfs)

pullkernel_directfb_armhf: debian_directfb_armhf.disk
	$(call mount_rootfs,$<)
	sudo cp tmp.mnt/boot/initrd.img-5.16.0-1-armmp tmp.mnt/boot/vmlinuz-5.16.0-1-armmp ./
	$(call unmount_rootfs)

run_debian_directfb_armhf:
	qemu-system-arm -M virt,highmem=off				    	\
		-smp 4								\
		-device virtio-gpu-pci						\
		-drive file=debian_directfb_armhf.disk,format=raw		\
		-m 1024M							\
		-kernel vmlinuz-5.16.0-1-armmp					\
		-initrd initrd.img-5.16.0-1-armmp				\
		-append "root=/dev/vda rw"
