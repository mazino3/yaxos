; YaxOS interrupt definitions.
bits 16

; The interrupt numbers.
INTERRUPT_SYSTEM        equ 0x20
INTERRUPT_CONSOLE       equ 0x21
INTERRUPT_SHELL         equ 0x22

; The system functions.
SYSTEM_KALLOC           equ 0
SYSTEM_KFREE            equ 1

; The console functions.
CONSOLE_PRINT           equ 0
CONSOLE_PRINTF          equ 1
CONSOLE_NEWLINE         equ 2
CONSOLE_PRINTCHAR       equ 3
CONSOLE_READLINE        equ 4

; The shell functions.
SHELL_ENUM_INIT         equ 0
SHELL_ENUM_NEXT         equ 1
SHELL_FINDENTRY         equ 2
SHELL_READFILE          equ 3
SHELL_CHANGEDIRECTORY   equ 4
