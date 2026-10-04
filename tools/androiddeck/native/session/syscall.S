// SPDX-License-Identifier: GPL-3.0-only
// Forward ordinary variadic calls unchanged, without reading absent arguments.
#include <asm/unistd.h>
.text
.p2align 2
.global syscall
.type syscall, %function
.hidden deck_real_syscall
.hidden deck_get_robust_list
.hidden deck_missing_syscall
syscall:
    bti c
    cmp x0, #__NR_get_robust_list
    b.eq deck_get_robust_list
    adrp x16, deck_real_syscall
    ldr x16, [x16, :lo12:deck_real_syscall]
    cbz x16, deck_missing_syscall
    br x16
.size syscall, .-syscall
.section .note.GNU-stack,"",%progbits
