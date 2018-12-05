yaxos - Yet Another eXperimental OS
===================================

YaxOS is my latest OSdev experiment.
It's a primitive operating system which can boot off (and read) a FAT32 volume.


It boots into a simple shell with a few commands.
    `ls` lists the files in the current directory.
    `cd` changes the current directory to a subdirectory (no paths supported).
    `cat` prints the contents of a given file.
    `run` loads a file into memory and executes it.
    `help` prints a help message.


The root directory in the disk image built with the Makefile contains a directory structure for testing purposes.
There's also a file called `testprog.com`, which is a test program that prints a "Hello, World!" message and lists the files
 in the current directory, demonstrating the system calls.

`cd` accepts a special directory name, `:root`, which changes the current directory to the root directory of the partition.


Writing to the disk is not supported yet.


To build the disk image in `boot/disk.img`, run `make` (requires nasm, mtools and parted).
There's also an option to run the disk image in QEMU after building it, do `make test`.
