all: clean kernel/kernel.bin boot/disk.img test-program/testprog.com

clean:
	cd kernel && make clean
	cd boot && make clean
	cd test-program && make clean

kernel/kernel.bin:
	cd kernel && make

boot/disk.img: kernel/kernel.bin test-program/testprog.com
	cd boot && make

test-program/testprog.com:
	cd test-program && make

test: all
	qemu-system-i386 -hda boot/disk.img
