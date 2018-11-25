all: clean kernel/kernel.bin boot/disk.img

clean:
	cd kernel && make clean
	cd boot && make clean

kernel/kernel.bin:
	cd kernel && make

boot/disk.img:
	cd boot && make

test: all
	qemu-system-i386 -hda boot/disk.img
