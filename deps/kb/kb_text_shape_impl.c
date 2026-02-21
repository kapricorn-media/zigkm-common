#include <stddef.h>
#include <stdint.h>

void* stb_zig_memset(void* str, int c, size_t n);
void zig_print(char* msg, uint32_t arg1, uint32_t arg2, uint32_t arg3, uint32_t arg4);

#define KB_TEXT_SHAPE_IMPLEMENTATION
#define KB_TEXT_SHAPE_NO_CRT
#define KBTS_MEMSET stb_zig_memset
#include "kb_text_shape.h"
