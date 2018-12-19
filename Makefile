all: clean kernel/kernel.bin boot/disk.img utils/*.com

clean:
	cd kernel && make clean
	cd boot && make clean
	cd utils && make clean

kernel/kernel.bin:
	cd kernel && make

boot/disk.img: kernel/kernel.bin utils/*.com
	cd boot && make

utils/*.com:
	cd utils && make

test: all
	qemu-system-i386 -hda boot/disk.img
