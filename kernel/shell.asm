; YaxOS shell
bits 16

%include "string.asm"

; The commands can be up to 256 characters long.
SHELL_COMMAND_BUFFER_SIZE equ 256

; The current status of the shell
shell._status:
    .FATContextSegment       dw 0
    .currentDirectorySegment dw 0
    .currentDirectoryLength  dw 0
    .commandBufferSegment    dw 0


; Initializes the shell.
; GS points to the FATContext structure of the root partition.
shell.init:
    push eax
    push cx
    push si
    push fs

    ; Log
    mov si, shell.initMessage
    call console.print

    ; Preserve the FAT context segment
    mov [shell._status.FATContextSegment], gs

    ; Log
    mov si, shell.readRootMessage
    call console.print

    ; Read the root directory and make it the current one.
    mov eax, [gs:FATContext.rootCluster]
    call fat32.readClusterChain
    jc shell.error

    ; Update the status
    mov [shell._status.currentDirectorySegment], fs
    mov [shell._status.currentDirectoryLength], cx

    ; Allocate the buffers
    mov si, shell.allocMessage

    ; Allocate the command buffer
    mov cx, SHELL_COMMAND_BUFFER_SIZE
    call kalloc.kalloc
    jc shell.error

    mov [shell._status.commandBufferSegment], fs

    ; Init done
    mov si, shell.initDoneMessage
    call console.print

    ; Return
    pop fs
    pop si
    pop cx
    pop eax
    ret


; Reports an error and halts.
shell.error:
    mov si, shell.errorMessage
    call console.print
    jmp kernel.halt


; Lists the files in the current directory along with their attributes.
shell.listFiles:
    push eax
    push bx
    push ecx
    push si
    push bp
    push fs

    ; Load the current directory segment.
    mov fs, [shell._status.currentDirectorySegment]
    mov bp, [shell._status.currentDirectoryLength]

.nextEntry:
    ; Parse the directory entry at FS.
    mov si, .tempFilename
    call fat32.parseDirEntry
    jc .done

    ; Type character
    mov [.tempFilenameType], byte '-'

    ; BL contains the attributes.
    test bl, FAT_ATTRIBUTE_DIRECTORY
    jz .skipDirectory

    ; Change the type to '+'
    mov [.tempFilenameType], byte '+'

    ; Skip
.skipDirectory:
    ; Print the filename.
    mov si, .tempFilenameLine
    call console.print
    call console.newline

    ; Next directory entry.
    mov ax, fs
    add ax, FAT_SEGMENTS_PER_DIR_ENTRY
    mov fs, ax

    ; Done?
    sub bp, FATDirEntry.size
    jnz .nextEntry

.done:
    ; Done, restore registers and exit.
    pop fs
    pop bp
    pop si
    pop ecx
    pop bx
    pop eax
    ret

.tempFilenameLine:
.tempFilenameType db 0
    db " "
.tempFilename times 13 db 0


; Find a directory entry in the current directory whose filename matches that at ES:DI.
; Returns with CF set if the file has not been found.
; EAX, ECX, BL will be set appropriately.
shell.findEntry:
    push si
    push bp
    push fs

    ; Load the segment of the current directory
    mov fs, [shell._status.currentDirectorySegment]
    mov bp, [shell._status.currentDirectoryLength]

.loop:
    ; Read the directory entry.
    mov si, .tempFilename
    call fat32.parseDirEntry

    ; If this entry is empty, stop
    jc .notFound

    ; Compare the filenames, return if they match.
    call string.compare
    jz .return

    ; Next entry
    mov ax, fs
    add ax, FAT_SEGMENTS_PER_DIR_ENTRY
    mov fs, ax
    sub bp, FATDirEntry.size
    jnz .loop

    ; No more entries, not found.
    jmp .notFound

    ; Done, return
.done:
    ; No carry
    clc
.return:
    pop fs
    pop bp
    pop si
    ret
.notFound:
    ; Set carry
    stc
    jmp .return

.tempFilename times 13 db 0


; Change the current directory to the one referred to by ES:DI.
shell.changeDirectory:
    push eax
    push ecx
    push fs
    push gs
    push si

    ; Search for a directory entry with a given name.
    call shell.findEntry
    jc .notFound

    ; Test is it's a directory.
    test bl, FAT_ATTRIBUTE_DIRECTORY
    jz .notADirectory

    ; Restore the segments.
    mov fs, [shell._status.currentDirectorySegment]
    mov gs, [shell._status.FATContextSegment]

    ; Free the cluster chain for the old directory.
    call kalloc.kfree

    ; If EAX is zero, replace it with the starting cluster of the root directory.
    test eax, eax
    jnz .skipRoot
    mov eax, [gs:FATContext.rootCluster]
.skipRoot:

    ; Read the cluster chain for the current directory.
    call fat32.readClusterChain

    ; If that fails, report error.
    jc .readError

    ; Write the new segment address
    mov [shell._status.currentDirectorySegment], fs
    mov [shell._status.currentDirectoryLength], cx

.done:
    ; No carry
    clc

    ; Return
.return:
    pop si
    pop gs
    pop fs
    pop ecx
    pop eax
    ret

.error:
    ; Set carry
    stc
    jmp .return

.notFound:
    mov si, .notFoundMessage
    call console.print
    jmp .error

.notADirectory:
    mov si, .notADirectoryMessage
    call console.print
    jmp .error

.readError:
    mov si, .readErrorMessage
    call console.print
    jmp shell.error

.notFoundMessage db "cd: directory not found.", 13, 10, 0
.notADirectoryMessage db "cd: not a directory.", 13, 10, 0
.readErrorMessage db "cd: read error, halting the shell.", 13, 10, 0


; Reads a file (ES:DI contains the filename).
; ES will point to the buffer read, CX bytes long.
shell.readFile:
    push eax
    push bx
    push fs
    push gs

    ; Search for a directory entry with a given name.
    call shell.findEntry
    jc .notFound

    ; Test is it's a directory.
    test bl, FAT_ATTRIBUTE_DIRECTORY
    jnz .fileExpected

    ; Restore the FAT context segment.
    mov gs, [shell._status.FATContextSegment]

    ; Read the cluster chain
    push cx
    call fat32.readClusterChain
    pop cx
    jc .readError

    ; FS -> ES
    push fs
    pop es

    ; No carry
    clc

.return:
    pop gs
    pop fs
    pop bx
    pop eax
    ret

.error:
    ; Set carry, return
    stc
    jmp .return

.notFound:
    mov si, .notFoundMessage
    call console.print
    jmp .error

.fileExpected:
    mov si, .fileExpectedMessage
    call console.print
    jmp .error

.readError:
    mov si, .readErrorMessage
    call console.print
    jmp .error

.notFoundMessage db "readFile: file not found.", 13, 10, 0
.fileExpectedMessage db "readFile: file expected.", 13, 10, 0
.readErrorMessage db "readFile: read error.", 13, 10, 0


; The main loop of the shell (get command, etc).
shell.mainLoop:
.waitCommand:
    mov si, shell.commandPrompt
    call console.print

    ; Read a command into the command buffer
    mov es, [shell._status.commandBufferSegment]
    xor di, di
    mov cx, SHELL_COMMAND_BUFFER_SIZE
    call console.readLine

    ; Find the first space character (BX will be zero if it's at the beginning or there are no spaces in the command).
    xor bx, bx
.findSpace:
    ; Load a character
    mov al, [es:bx]

    ; Space?
    cmp al, ' '
    jz .spaceFound

    ; Zero?
    cmp al, 0
    jz .spaceNotFound

    ; Loop
    inc bx
    jmp .findSpace

.spaceFound:
    ; Terminate the command where the space is.
    mov byte [es:bx], 0
    inc bx
    jmp .findSpaceDone
.spaceNotFound:
    ; Clear BX.
    xor bx, bx

.findSpaceDone:
    ; If the command is empty, try again
    cmp [es:di], byte 0
    jz .waitCommand

    ; Compare the commands
    mov si, shell.commandHelp
    call string.compare
    jz .commandHelp

    mov si, shell.commandLS
    call string.compare
    jz .commandLS

    mov si, shell.commandCD
    call string.compare
    jz .commandCD

    mov si, shell.commandCat
    call string.compare
    jz .commandCat

    mov si, shell.commandRun
    call string.compare
    jz .commandRun

    ; Invalid command
    mov si, shell.invalidCommandMessage
    call console.print

    jmp .waitCommand

.commandHelp:
    mov si, shell.helpMessage
    call console.print
    jmp .waitCommand

.commandLS:
    call shell.listFiles
    jmp .waitCommand

.commandCD:
    ; Change the current directory.
    ; CD requires an argument.
    test bx, bx
    jz .noArgument

    ; Change the directory
    mov di, bx
    call shell.changeDirectory

    jmp .waitCommand

.commandCat:
    ; cat requires an argument.
    test bx, bx
    jz .noArgument

    ; Read the file into ES.
    mov di, bx
    call shell.readFile

    ; On error, wait for the next command.
    jc .waitCommand

    xor di, di
.printChar:
    test cx, cx
    jz .printDone

    ; Print the character at ES:DI
    mov al, [es:di]
    inc di
    call console.printChar

    ; Next character
    dec cx
    jmp .printChar

.printDone:
    ; Release the memory the file was read into.
    call kalloc.kfree

    ; Newline
    call console.newline
    jmp .waitCommand

.commandRun:
    ; run requires an argument.
    test bx, bx
    jz .noArgument

    ; Read the file into ES.
    mov di, bx
    call shell.readFile

    ; On error, wait for the next command.
    jc .waitCommand

    ; Jump into the loaded program
    mov [.farJumpSegment], es

    pusha
    push ds
    push es
    push fs
    push gs
    call far [.farJump]
    pop gs
    pop fs
    pop es
    pop ds
    popa

    ; Free the memory allocated.
    call kalloc.kfree
    jmp .waitCommand

.noArgument:
    mov si, shell.noArgumentMessage
    call console.print
    jmp .waitCommand

.farJump:
.farJumpOffset dw 0
.farJumpSegment dw 0


shell.errorMessage db "[!] shell: error, halting.", 13, 10, 0
shell.initMessage db "[+] shell: initializing...", 13, 10, 0
shell.readRootMessage db "[+] shell: reading root directory...", 13, 10, 0
shell.allocMessage db "[+] shell: allocating memory for buffers...", 13, 10, 0
shell.initDoneMessage db "[+] shell: initialization done.", 13, 10, 0

shell.commandPrompt db "YaxOS> ", 0
shell.invalidCommandMessage db "error: invalid command, type 'help' for a list.", 13, 10, 0
shell.noArgumentMessage db "error: this command requires an argument.", 13, 10, 0

shell.commandHelp db "help", 0
shell.commandLS db "ls", 0
shell.commandCD db "cd", 0
shell.commandCat db "cat", 0
shell.commandRun db "run", 0

shell.helpMessage db "Available commands: help, ls, cd, cat, run.", 13, 10, 0
