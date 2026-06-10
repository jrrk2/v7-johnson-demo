#include <stdint.h>
#define reg_uart_clkdiv (*(volatile uint32_t*)0x02000004)
#define reg_uart_data   (*(volatile uint32_t*)0x02000008)
#define reg_leds        (*(volatile uint32_t*)0x03000000)

static void putchar_(char c) { reg_uart_data = c; }
static void print(const char *s) { while (*s) putchar_(*s++); }

void main(void) {
    reg_leds = 1;
    // 100 MHz / (clkdiv + 1) = 115200  ->  clkdiv = 867
    reg_uart_clkdiv = 867;
    reg_leds = 0xAA;

    uint32_t pat = 1;
    for (;;) {
        print("PicoSoC alive on VC707 @ 100 MHz (open flow)\r\n");
        for (volatile int i = 0; i < 2000000; i++)
            ;
        pat = (pat == 0x80) ? 1 : pat << 1;
        reg_leds = pat;
    }
}
