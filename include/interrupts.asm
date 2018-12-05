; YaxOS interrupt definitions.
bits 16

; The interrupt numbers.
INTERRUPT_SYSTEM  equ 0x20
INTERRUPT_CONSOLE equ 0x21

; The system functions.
SYSTEM_KALLOC     equ 0
SYSTEM_KFREE      equ 1

; The console functions.
CONSOLE_PRINT     equ 0
CONSOLE_PRINTF    equ 1
CONSOLE_NEWLINE   equ 2
CONSOLE_PRINTCHAR equ 3
CONSOLE_READLINE  equ 4
