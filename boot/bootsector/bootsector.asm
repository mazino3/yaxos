; A bootsector to load the kernel from a FAT32 partition.
org 0
bits 16

; The first 90 bytes are the FAT32 BPB (BIOS Parameter Block) and are going to be replaced by the Makefile.

BPB:
    .jump                   times 3 db 0
    .oemId                  times 8 db 0
    .wBytesPerSector        dw 0
    .bSectorsPerCluster     db 0
    .wReservedSectors       dw 0
    .bNumFATs               db 0
    .wRootEntries           dw 0
    .wTotalSectors          dw 0
    .bMediaDescriptor       db 0
    .wSectorsPerFAT         dw 0
    .wSectorsPerTrack       dw 0
    .wNumHeads              dw 0
    .dHiddenSectors         dd 0
    .dTotalSectors          dd 0
extBPB:
    .dSectorsPerFAT         dd 0
    .wFlags                 dw 0
    .wFATVersion            dw 0
    .dRootCluster           dd 0
    .wFSInfoSector          dw 0
    .wBackupBootSector      dw 0
    .reserved               times 12 db 0
    .bDriveNumber           db 0
    .bWinNTFlags            db 0
    .bSignature             db 0
    .dVolumeSerial          dd 0
    .volumeLabel            times 11 db 0
    .systemIdentifier       times 8 db 0

; Ensure that CS is set to 0x7c0
jmp 0x7c0:start

; The Disk Address Packet, used by readFAT and readCluster
dap:
    .size       db 16
    .unused     db 0
    .numSectors dw 0

    .offset     dw 0
    .segment    dw 0
    .startLBA   dd 0
    .startLBAHi dd 0


; Reads the EAX'th FAT entry, returns the value in EAX.
readFAT:
    ; Multiply EAX by 4 (the size of a FAT entry)
    shl eax, 2

    ; Find the offset into the sector
    mov bx, ax
    and bx, 0x1ff

    ; Divide EAX by 512, the sector size
    shr eax, 9

    ; Add the FAT offset
    add eax, [status.FATOffset]


    ; EAX is the sector we want, BX is the offset into that sector.

    ; Initialize the DAP.
    mov [dap.startLBA], eax
    mov [dap.segment], fs
    mov [dap.offset], word 0
    mov [dap.numSectors], word 1

    ; Debug (print 'f')
    mov ax, 0x0e66
    int 10h

    ; Read the FAT sector
    mov ah, 0x42
    mov dl, [status.driveNumber]
    mov si, dap
    int 13h

    ; If the carry flag is set, then a read error has occured.
    jc readError

    ; Read the FAT entry
    mov eax, [fs:bx]
    and eax, 0x0fffffff

    ; If EAX is the EOF value, just set it to zero.
    cmp eax, 0x0ffffff8
    jnae .skipZero
    xor eax, eax
.skipZero:
    ret


; Reads the EAX'th data cluster into ES:DI.
readCluster:
    ; Cluster numbers start with 2
    sub eax, 2

    ; Find the starting sector
    xor cx, cx
    mov cl, [BPB.bSectorsPerCluster]

    ; EAX*CX -> EDX:EAX
    mul cx

    ; EAX now points to the correct sector.
    add eax, [status.dataOffset]

    ; Initialize the DAP.
    mov [dap.startLBA], eax
    mov [dap.segment], es
    mov [dap.offset], di
    mov [dap.numSectors], cx

    ; Debug (print 'd')
    mov ax, 0x0e64
    int 10h

    ; Read the cluster
    mov ah, 0x42
    mov dl, [status.driveNumber]
    mov si, dap
    int 13h

    ; If the carry flag is set, then a read error has occured.
    jc readError

    ; Done
    ret

start:
    ; Clear the direction flag
    cld

    ; Set DS to CS
    mov ax, cs
    mov ds, ax

    ; Place the stack at the top of the current segment.
    ; No cli needed, as mov ss, x will inhibit interrupts until the next instruction is executed.
    mov ss, ax
    xor sp, sp

    ; Initialize FS
    mov ax, 0x50
    mov fs, ax

    ; Store the current drive number
    mov [status.driveNumber], dl

    ; Find the FAT offset
    mov eax, [BPB.dHiddenSectors]

    ; Add the number of reserved sectors
    xor ebx, ebx
    mov bx, [BPB.wReservedSectors]
    add eax, ebx

    ; Store
    mov [status.FATOffset], eax

    ; Preserve EAX
    mov ebx, eax

    ; Find the data cluster offset
    mov eax, [extBPB.dSectorsPerFAT]

    ; Set CX to the number of FATs.
    xor cx, cx
    mov cl, [BPB.bNumFATs]

    ; EAX*CX -> EDX:EAX
    mul cx

    ; Add the previous offset
    add eax, ebx

    ; Store the data offset
    mov [status.dataOffset], eax

    ; Find the number of directory entries per cluster.
    mov cx, [BPB.bSectorsPerCluster]

    ; Multiply by 16, as it's the number of 32-byte directory entries per a 512-byte sector.
    shl cx, 4

    ; Store the value
    mov [status.dirsPerCluster], cx


    ; Read the root clusters.

    ; The buffer is at 0050:0000.
    mov ax, 0x50
    mov es, ax

    ; Read the first cluster of the root directory
    mov eax, [extBPB.dRootCluster]

.nextRootCluster:
    ; Clear DI
    xor di, di

    push eax
    call readCluster
    pop eax

    ; Iterate CX times
    mov cx, [status.dirsPerCluster]
    xor di, di

.nextEntry:
    ; Compare the filenames
    push si
    push di
    push cx

    mov si, filename
    mov cx, 11
    rep cmpsb
    jz .found

    pop cx
    pop di
    pop si

    ; Next entry
    add di, 32
    dec cx
    jnz .nextEntry

    ; Find the number of the next cluster
    call readFAT
    jnz .nextRootCluster

    ; File not found, print 'N'
    mov ax, 0x0e4e
    int 10h
    jmp halt

.found:
    ; Restore the registers
    pop cx
    pop di
    pop si

    ; Print 'F'
    mov ax, 0x0e46
    int 10h

    ; Load the number of the next cluster
    mov ax, [es:di+20]
    shl eax, 16
    mov ax, [es:di+26]

    ; We'll load the kernel at 17c0:0000.
    mov bx, 0x17c0
    mov es, bx
    xor di, di

    ; Load the next cluster of the file
.loadCluster:
    push eax
    call readCluster
    pop eax

    add di, 512
    jnz .skipOverflow

    ; Next 64KB
    mov bx, es
    add bx, 0x1000
    mov es, bx

.skipOverflow:
    ; Read the next FAT entry
    call readFAT
    jnz .loadCluster

    ; Print 'D'
    mov ax, 0x0e44
    int 10h

    ; Transfer control to the kernel
    xor sp, sp
    jmp 0x17c0:0

halt:
    hlt
    jmp halt

readError:
    ; Print '!'
    mov ax, 0x0e21
    int 10h

    jmp halt

status:
    .driveNumber    db 0

    ; LBA offsets into the first FAT and the data clusters.
    .FATOffset      dd 0
    .dataOffset     dd 0

    ; Directory entries per cluster.
    .dirsPerCluster dw 0

filename db "KERNEL  BIN"

times 510-($-$$) db 0
dw 0xaa55
