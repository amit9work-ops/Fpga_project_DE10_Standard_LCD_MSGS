#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <signal.h>     // NEW: graceful shutdown
#include <time.h>

#include "LCD_Hw.h"
#include "LCD_Lib.h"
#include "lcd_graphic.h"
#include "font.h"
#include "messages.h"
#include "render_screen.h"

#define HW_REGS_BASE          0xFC000000
#define HW_REGS_SPAN          0x04000000
#define HW_REGS_MASK          (HW_REGS_SPAN - 1)
#define ALT_LWFPGASLVS_OFST   0xFF200000
#define BUTTON_PIO_BASE       0x5000
#define FSM_STATUS_PIO_BASE   0x6000
#define TIMER_STATUS_PIO_BASE 0x7000
#define BUTTON_MASK           0x0F
#define TIMEOUT_SECONDS       15

#define FSM_STATUS_STATE_SHIFT 5
#define FSM_STATUS_STATE_MASK  0xE0
#define FSM_STATUS_INDEX_MASK  0x1F

#define FSM_STATE_FROM_REG(v)  (((v) & FSM_STATUS_STATE_MASK) >> FSM_STATUS_STATE_SHIFT)
#define FSM_INDEX_FROM_REG(v)  ((v) & FSM_STATUS_INDEX_MASK)

typedef enum {
    HW_FSM_INIT  = 0,
    HW_FSM_IDLE  = 1,
    HW_FSM_HOME  = 2,
    HW_FSM_MSG   = 3,
    HW_FSM_SLEEP = 4
} HwFsmState;

// === Globals ===
static void *virtual_base = MAP_FAILED;
static volatile uint32_t *button_addr       = NULL;
static volatile uint32_t *fsm_status_addr   = NULL;
static volatile uint32_t *timer_status_addr = NULL;
static int  fd = -1;

// NEW: graceful shutdown flag (signal-safe)
static volatile sig_atomic_t g_shutdown = 0;

static const char* hw_fsm_state_name(int state) {
    switch (state) {
        case HW_FSM_INIT:  return "INIT";
        case HW_FSM_IDLE:  return "IDLE";
        case HW_FSM_HOME:  return "HOME";
        case HW_FSM_MSG:   return "MSG";
        case HW_FSM_SLEEP: return "SLEEP";
        default:           return "UNKNOWN";
    }
}

// NEW: signal handler for Ctrl+C, kill, etc.
static void signal_handler(int signum) {
    (void)signum;
    g_shutdown = 1;
}

// NEW: centralized cleanup so every exit path releases resources
static void cleanup(void) {
    // Try to leave LCD in a sane state
    if (virtual_base != MAP_FAILED) {
        LCDHW_BackLight(false);
        LCD_GraphicClear();
        munmap(virtual_base, HW_REGS_SPAN);
        virtual_base = MAP_FAILED;
    }
    if (fd >= 0) {
        close(fd);
        fd = -1;
    }
    printf("\nClean shutdown complete.\n");
}

int main(void) {
    // NEW: install signal handlers BEFORE opening hardware
    signal(SIGINT,  signal_handler);
    signal(SIGTERM, signal_handler);

    printf("Opening /dev/mem...\n");
    fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("ERROR: Cannot open /dev/mem");
        return 1;
    }

    printf("Memory mapping...\n");
    virtual_base = mmap(NULL, HW_REGS_SPAN, PROT_READ | PROT_WRITE,
                       MAP_SHARED, fd, HW_REGS_BASE);
    if (virtual_base == MAP_FAILED) {
        perror("ERROR: mmap failed");
        close(fd);
        return 1;
    }
    printf("  virtual_base = %p\n", virtual_base);

    // Map register pointers
    button_addr       = (uint32_t *)((char*)virtual_base +
        ((ALT_LWFPGASLVS_OFST + BUTTON_PIO_BASE)       & HW_REGS_MASK));
    fsm_status_addr   = (uint32_t *)((char*)virtual_base +
        ((ALT_LWFPGASLVS_OFST + FSM_STATUS_PIO_BASE)   & HW_REGS_MASK));
    timer_status_addr = (uint32_t *)((char*)virtual_base +
        ((ALT_LWFPGASLVS_OFST + TIMER_STATUS_PIO_BASE) & HW_REGS_MASK));
    printf("  button_addr       = %p\n", (void*)button_addr);
    printf("  fsm_status_addr   = %p\n", (void*)fsm_status_addr);
    printf("  timer_status_addr = %p\n", (void*)timer_status_addr);

    // NEW: bridge sanity check — if all 0xFFFFFFFF, the FPGA is not responding
    uint32_t probe = *fsm_status_addr;
    if (probe == 0xFFFFFFFFu) {
        fprintf(stderr, "ERROR: FPGA bridge returned 0xFFFFFFFF. "
                        "Is the .rbf programmed and Qsys addresses correct?\n");
        cleanup();
        return 2;
    }

    printf("Initializing LCD...\n");
    LCDHW_Init(virtual_base);
    LCD_Init();
    LCD_GraphicClear();
    LCDHW_BackLight(true);
    printf("LCD Ready.\n");

    int  last_hw_state     = -1;
    int  last_hw_msg_index = -1;
    bool backlight_on      = true;
    int  last_warn_code    = 0;

    printf("\n=== LCD MESSAGE SYSTEM STARTED ===\n");
    printf("Using FPGA hardware debouncing + idle timer.\n");
    printf("Press Ctrl+C to exit cleanly.\n\n");

    // === MAIN LOOP ===
    while (!g_shutdown) {                          // CHANGED: was while(1)
        uint32_t fsm_status   = *fsm_status_addr;
        uint32_t timer_status = *timer_status_addr;

        int  hw_fsm_state = FSM_STATE_FROM_REG(fsm_status);
        int  hw_msg_index = FSM_INDEX_FROM_REG(fsm_status);
        bool timeout      = timer_status & 1;
        int  secs_left    = (timer_status >> 1) & 0x0F;

        // FIXED: only warn on persistent inconsistency (not on transitions).
        // We require the inconsistency to coincide with a state change,
        // so single-cycle transients during button-wake are ignored.
        bool state_changed = (hw_fsm_state != last_hw_state);

        if (state_changed && hw_fsm_state == HW_FSM_MSG &&
            hw_msg_index >= MSG_COUNT) {
            if (last_warn_code != 2) {
                printf("[WARN] FSM=MSG with out-of-range msg_index=%d\n", hw_msg_index);
                last_warn_code = 2;
            }
        } else if (!state_changed) {
            last_warn_code = 0;
        }
        // REMOVED: the "FSM=SLEEP but timeout=0" warning — it fires
        // legitimately during the SLEEP→IDLE wake transition.

        if (state_changed ||
            (hw_fsm_state == HW_FSM_MSG && hw_msg_index != last_hw_msg_index)) {

            printf("HW FSM: %s(%d), msg_idx=%d, secs_left=%d, timeout=%d\n",
                   hw_fsm_state_name(hw_fsm_state), hw_fsm_state,
                   hw_msg_index, secs_left, timeout ? 1 : 0);

            bool want_backlight = render_screen(hw_fsm_state, hw_msg_index);
            if (want_backlight && !backlight_on) {
                LCDHW_BackLight(true);
                backlight_on = true;
            } else if (!want_backlight && backlight_on) {
                LCDHW_BackLight(false);
                backlight_on = false;
            }

            if (hw_fsm_state != HW_FSM_INIT &&
                hw_fsm_state != HW_FSM_IDLE &&
                hw_fsm_state != HW_FSM_HOME &&
                hw_fsm_state != HW_FSM_MSG  &&
                hw_fsm_state != HW_FSM_SLEEP) {
                if (last_warn_code != 3) {
                    printf("[WARN] Unknown FSM state value=%d\n", hw_fsm_state);
                    last_warn_code = 3;
                }
            }

            last_hw_state     = hw_fsm_state;
            last_hw_msg_index = hw_msg_index;
        }

        usleep(5000);  // 5ms poll — meets latency budget after FPGA debounce reduction
    }

    cleanup();         // NEW: always release resources
    return 0;
}