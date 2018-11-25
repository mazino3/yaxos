; YaxOS memory allocation code
bits 16

; We're allocating memory in 256-byte chunks.
; The kernel heap is located at 0x37c00 and the available memory ends at 0x80000.
KERNEL_HEAP_START equ 0x37c00
KERNEL_HEAP_END   equ 0x80000
KERNEL_HEAP_SIZE  equ KERNEL_HEAP_END - KERNEL_HEAP_START

; Block size
ALLOC_BLOCK_SIZE_POWER  equ 8
ALLOC_BLOCK_SIZE        equ 1<<ALLOC_BLOCK_SIZE_POWER
KERNEL_HEAP_BLOCKS      equ KERNEL_HEAP_SIZE / ALLOC_BLOCK_SIZE

; The segment where the kernel heap starts.
KERNEL_HEAP_START_SEGMENT   equ KERNEL_HEAP_START>>4

; The count of segments per allocation block.
ALLOC_SEGMENTS_PER_BLOCK    equ ALLOC_BLOCK_SIZE>>4

; Flags for kalloc._allocMap
ALLOC_FREE  equ 0x00
ALLOC_USED  equ 0xff

; Allocation header, for kalloc.kalloc
struc allocHeader
    .blockIndex resw 1
    .blocksUsed resw 1

    ; Make sure the header is 16 bytes long.
    resb 14
endstruc


; The allocation map
kalloc._allocMap times KERNEL_HEAP_BLOCKS db 0


; Initializes the allocator.
kalloc.init:
    ; Preserve the registers
    push ax
    push cx
    push di

    ; Store KERNEL_HEAP_BLOCKS ALLOC_FREEs in the kernel allocation map.
    mov al, ALLOC_FREE
    mov cx, KERNEL_HEAP_BLOCKS
    mov di, kalloc._allocMap
    rep stosb

    ; Restore the registers, done.
    pop di
    pop cx
    pop ax

    ret

; Looks for a contiguous chain of CX heap blocks and returns the pointer to it in SI.
; If no free blocks are available, returns with CF set.
kalloc.allocBlocks:
    push ax
    push cx
    push dx
    push di

    ; Preserve CX
    mov dx, cx

    ; SI points to the beginning of the allocation map.
    mov si, kalloc._allocMap

.checkBlock:
    ; Compare the map entries to the free marker.
    ; If the loop exits prematurely, it means that an allocated block was encountered somewhere
    ;  so we have to try again.

    mov di, si
    mov cx, dx
    mov al, ALLOC_FREE
    rep scasb

    jz .found

    ; Next series of blocks
    inc si

    ; We're out of memory
    cmp si, kalloc._allocMap + KERNEL_HEAP_BLOCKS
    jz .error

    ; Check another block
    jmp .checkBlock

.found:
    ; Success, now mark those as allocated.
    mov al, ALLOC_USED
    mov cx, dx
    mov di, si
    rep stosb

    ; Clear carry
    clc

.return:
    pop di
    pop dx
    pop cx
    pop ax

    ret

.error:
    ; Set carry
    stc
    jmp .return


; Frees the blocks allocated by allocBlocks.
; SI points into the allocation table, CX is the count of blocks to free.
kalloc.freeBlocks:
    push ax
    push cx
    push di

    ; Write CX ALLOC_FREE bytes into the table
    mov al, ALLOC_FREE
    mov di, si
    rep stosb

    pop di
    pop cx
    pop ax

    ret


; Allocates at least CX bytes, FS:DI point to the allocated memory.
; Sets the carry flag if the allocation has failed.
kalloc.kalloc:
    push eax
    push ebx
    push cx
    push si

    ; Add the header length and round to the lowest higher or equal block
    add cx, 16 + 255
    shr cx, ALLOC_BLOCK_SIZE_POWER

    ; CX now contains the amount of blocks we want to allocate

    ; Try allocating blocks
    call kalloc.allocBlocks
    jc .error

    ; SI now points into the allocation map, find the starting address.
    xor eax, eax
    mov ax, si
    sub ax, kalloc._allocMap
    shl eax, ALLOC_BLOCK_SIZE_POWER
    add eax, KERNEL_HEAP_START

    ; Find the segment:offset
    mov ebx, eax
    and eax, 0xfffffff0

    ; BX is the offset
    sub ebx, eax

    ; AX is the segment
    shr eax, 4

    ; Initialize the allocation structure
    mov fs, ax
    mov di, bx

    mov [fs:di+allocHeader.blockIndex], si
    mov [fs:di+allocHeader.blocksUsed], cx

    ; Add a 16-byte offset (past the allocation structure)
    inc ax
    mov fs, ax

    ; Success
    clc

.done:
    ; Restore the registers, return
    pop si
    pop cx
    pop ebx
    pop eax

    ret

.error:
    ; Set carry
    stc
    jmp .done


; Frees a memory region allocated by kalloc.kalloc, FS:DI point to the block previously allocated.
kalloc.kfree:
    push ax
    push cx
    push si

    ; Decrement AX so that FS:DI points to the allocation structure.
    mov ax, fs
    dec ax
    mov fs, ax

    ; Call freeBlocks
    mov si, [fs:di+allocHeader.blockIndex]
    mov cx, [fs:di+allocHeader.blocksUsed]
    call kalloc.freeBlocks

    ; Restore the registers, done
    pop si
    pop cx
    pop ax
    ret
