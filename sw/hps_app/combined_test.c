#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "LCD_Hw.h"
#include "LCD_Lib.h"
#include "lcd_graphic.h"
#include "font.h"

#define HW_REGS_BASE          0xFC000000
#define HW_REGS_SPAN          0x04000000
#define HW_REGS_MASK          (HW_REGS_SPAN - 1)
#define ALT_LWFPGASLVS_OFST   0xFF200000
#define BUTTON_PIO_BASE       0x0140
#define BUTTON_MASK           0x0F

void *virtual_base = NULL;
volatile uint32_t *button_addr = NULL;

int main() {
    int fd;
    
    // === STEP 1: Open /dev/mem ===
    printf("Step 1: Opening /dev/mem...\n");
    fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        printf("ERROR: Cannot open /dev/mem\n");
        return 1;
    }
    printf("  OK\n");
    
    // === STEP 2: Memory map ===
    printf("Step 2: Memory mapping...\n");
    virtual_base = mmap(NULL, HW_REGS_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, fd, HW_REGS_BASE);
    if (virtual_base == MAP_FAILED) {
        printf("ERROR: mmap failed\n");
        close(fd);
        return 1;
    }
    printf("  virtual_base = %p\n", virtual_base);
    
    // === STEP 3: Calculate button address ===
    printf("Step 3: Setting up button address...\n");
    button_addr = (uint32_t *)(virtual_base + ((ALT_LWFPGASLVS_OFST + BUTTON_PIO_BASE) & HW_REGS_MASK));
    printf("  button_addr = %p\n", (void*)button_addr);
    
    // === STEP 4: Test buttons BEFORE LCD init ===
    printf("Step 4: Testing buttons BEFORE LCD init...\n");
    printf("  Press KEY0 now (you have 3 seconds)...\n");
    for (int i = 0; i < 30; i++) {
        uint32_t raw = *button_addr;
        uint32_t btn = (~raw) & BUTTON_MASK;
        if (btn != 0) {
            printf("  BUTTON DETECTED: raw=0x%X, btn=0x%X\n", raw, btn);
        }
        usleep(100000);
    }
    printf("  Done.\n");
    
    // === STEP 5: Initialize LCD ===
    printf("Step 5: Initializing LCD hardware...\n");
    LCDHW_Init(virtual_base);
    LCD_Init();
    LCD_GraphicClear();
    LCDHW_BackLight(true);
    printf("  LCD initialized.\n");
    
    // === STEP 6: Test buttons AFTER LCD init ===
    printf("Step 6: Testing buttons AFTER LCD init...\n");
    printf("  Press KEY0 now (you have 3 seconds)...\n");
    for (int i = 0; i < 30; i++) {
        uint32_t raw = *button_addr;
        uint32_t btn = (~raw) & BUTTON_MASK;
        if (btn != 0) {
            printf("  BUTTON DETECTED: raw=0x%X, btn=0x%X\n", raw, btn);
        }
        usleep(100000);
    }
    printf("  Done.\n");
    
    // === STEP 7: Display on LCD and test buttons ===
    printf("Step 7: Displaying on LCD and testing buttons...\n");
    LCD_GraphicClear();
    LCD_TextOut(0, 0,  "Button Test");
    LCD_TextOut(0, 16, "Press KEY0-KEY3");
    LCD_TextOut(0, 32, "Watch console");
    printf("  LCD text displayed.\n");
    
    printf("\n=== MAIN TEST LOOP ===\n");
    printf("Press buttons. Console should show which button.\n");
    printf("Press Ctrl+C to exit.\n\n");
    
    int lastBtn = 0;
    int counter = 0;
    char line[32];
    
    while (1) {
        uint32_t raw = *button_addr;
        int btn = (~raw) & BUTTON_MASK;
        
        // Detect button press (transition from 0 to non-0)
        if (btn != 0 && lastBtn == 0) {
            counter++;
            printf("PRESS #%d: btn=%d (KEY0=%d KEY1=%d KEY2=%d KEY3=%d)\n", 
                   counter, btn,
                   (btn >> 0) & 1,
                   (btn >> 1) & 1,
                   (btn >> 2) & 1,
                   (btn >> 3) & 1);
            
            // Update LCD to show button press
            LCD_GraphicClear();
            sprintf(line, "Press #%d", counter);
            LCD_TextOut(0, 0, line);
            sprintf(line, "Button: %d", btn);
            LCD_TextOut(0, 16, line);
            
            if (btn & 1) LCD_TextOut(0, 32, "KEY0 pressed");
            if (btn & 2) LCD_TextOut(0, 32, "KEY1 pressed");
            if (btn & 4) LCD_TextOut(0, 32, "KEY2 pressed");
            if (btn & 8) LCD_TextOut(0, 32, "KEY3 pressed");
        }
        
        lastBtn = btn;
        usleep(50000);
    }
    
    close(fd);
    return 0;
}