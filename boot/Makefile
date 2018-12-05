DISK_SIZE=16384
PART_START=1
PART_END=16383
PART_SIZE=16383

DD=dd
PARTED=/sbin/parted -s
MKFS_FAT=/sbin/mkfs.fat
MCOPY=MTOOLS_SKIP_CHECK=1 mcopy


all: clean disk.img

clean:
	rm -f disk.img mbr.bin bootsector.bin part.bin
	cd bootsector && make clean

disk.img: mbr.bin part.bin ../kernel/kernel.bin
	cat mbr.bin part.bin > disk.img

	$(MCOPY) -i disk.img@@$(PART_START)s ../kernel/kernel.bin \:\:/
	$(MCOPY) -s -i disk.img@@$(PART_START)s ../root/* \:\:/
	$(MCOPY) -i disk.img@@$(PART_START)s ../test-program/*.com \:\:/

mbr.bin:
	$(DD) if=/dev/zero of=mbr.bin bs=512 count=$(DISK_SIZE)
	$(PARTED) mbr.bin mklabel msdos
	$(PARTED) mbr.bin mkpart primary fat32 $(PART_START)s $(PART_END)s
	$(PARTED) mbr.bin set 1 boot on
	truncate -s 512 mbr.bin

part.bin: bootsector/bootsector.bin
	cp bootsector/bootsector.bin .
	$(DD) if=/dev/zero of=part.bin bs=512 count=$(PART_SIZE)
	$(MKFS_FAT) -F 32 -h 1 part.bin
	dd if=part.bin of=bootsector.bin bs=1 count=90 conv=notrunc
	dd if=bootsector.bin of=part.bin bs=512 count=1 conv=notrunc

bootsector/bootsector.bin:
	cd bootsector && make
