all: clean kernel/kernel.bin boot/disk.img test-program/test.bin

clean:
	cd kernel && make clean
	cd boot && make clean
	cd test-program && make clean

kernel/kernel.bin:
	cd kernel && make

boot/disk.img: kernel/kernel.bin test-program/test.bin
	cd boot && make

test-program/test.bin:
	cd test-program && make

test: all
	qemu-system-i386 -hda boot/disk.img
