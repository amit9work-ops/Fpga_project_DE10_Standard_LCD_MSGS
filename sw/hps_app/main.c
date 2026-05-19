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
#include <errno.h>
#include <dirent.h>
#include <limits.h>

#include "LCD_Hw.h"
#include "LCD_Lib.h"
#include "lcd_graphic.h"
#include "font.h"
#include "messages.h"

#define HPS_REGS_BASE         0xFC000000
#define HPS_REGS_SPAN         0x04000000

// Lightweight H2F base (fixed Cyclone V SoC physical address)
#define LW_H2F_BASE           0xFF200000

// From Platform Designer: mm_bridge_0.s0 window exposed to LW master
// 0x0000_0000 .. 0x0003_FFFF  => 0x0004_0000 bytes
#define LW_BRIDGE_SPAN        0x00040000

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
#define MSG_COUNT              18

typedef enum {
    HW_FSM_INIT  = 0,
    HW_FSM_IDLE  = 1,
    HW_FSM_HOME  = 2,
    HW_FSM_MSG   = 3,
    HW_FSM_SLEEP = 4
} HwFsmState;

// === Globals ===
static void *hps_virtual_base = MAP_FAILED;
static void *lw_virtual_base  = MAP_FAILED;
static volatile uint32_t *button_addr       = NULL;
static volatile uint32_t *fsm_status_addr   = NULL;
static volatile uint32_t *timer_status_addr = NULL;
static int  fd = -1;
static bool g_lcd_initialized = false;

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

static int try_enable_fpga_bridges_in_dir(const char *class_dir) {
    DIR *dir = opendir(class_dir);
    if (!dir) return -1;

    int enabled = 0;
    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) continue;

        char enable_path[PATH_MAX];
        int n = snprintf(enable_path, sizeof(enable_path), "%s/%s/enable", class_dir, ent->d_name);
        if (n < 0 || (size_t)n >= sizeof(enable_path)) continue;
        int efd = open(enable_path, O_WRONLY);
        if (efd < 0) continue;

        // Best-effort: enable bridge; ignore failures.
        ssize_t w = write(efd, "1\n", 2);
        if (w > 0) enabled++;
        close(efd);
    }

    closedir(dir);
    return enabled;
}

// Some Terasic/Linux images leave HPS<->FPGA bridges disabled until enabled via sysfs.
// If this is the root cause of the hang, enabling here prevents the first MMIO read from stalling.
static void try_enable_fpga_bridges(void) {
    int c1 = try_enable_fpga_bridges_in_dir("/sys/class/fpga_bridge");
    int c2 = try_enable_fpga_bridges_in_dir("/sys/class/fpga-bridge");
    if (c1 >= 0 || c2 >= 0) {
        printf("FPGA bridge enable: fpga_bridge=%d, fpga-bridge=%d\n", c1, c2);
    } else {
        printf("FPGA bridge enable: no sysfs bridge class found (skipping)\n");
    }
}

static bool lw_offset_in_range(uint32_t offset, const char *name) {
    if ((uint64_t)offset + sizeof(uint32_t) > (uint64_t)LW_BRIDGE_SPAN) {
        fprintf(stderr,
                "ERROR: %s offset 0x%08X is outside LW bridge span (0x%08X bytes)\n",
                name, offset, (unsigned)LW_BRIDGE_SPAN);
        return false;
    }
    return true;
}

// NEW: centralized cleanup so every exit path releases resources
static void cleanup(void) {
    // Try to leave LCD in a sane state
    if (g_lcd_initialized) {
        LCDHW_BackLight(false);
        LCD_GraphicClear();
    }

    if (lw_virtual_base != MAP_FAILED) {
        munmap(lw_virtual_base, LW_BRIDGE_SPAN);
        lw_virtual_base = MAP_FAILED;
    }
    if (hps_virtual_base != MAP_FAILED) {
        munmap(hps_virtual_base, HPS_REGS_SPAN);
        hps_virtual_base = MAP_FAILED;
    }
    if (fd >= 0) {
        close(fd);
        fd = -1;
    }
    printf("\nClean shutdown complete.\n");
}

int main(void) {
    // Make prints visible immediately (helps pinpoint exactly where a hang occurs)
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    // NEW: install signal handlers BEFORE opening hardware
    signal(SIGINT,  signal_handler);
    signal(SIGTERM, signal_handler);

    // Best-effort enable of FPGA bridges (if supported by this Linux image)
    try_enable_fpga_bridges();

    printf("Opening /dev/mem...\n");
    fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("ERROR: Cannot open /dev/mem");
        return 1;
    }

    printf("Memory mapping (HPS regs @ 0x%08X, span 0x%08X)...\n",
           (unsigned)HPS_REGS_BASE, (unsigned)HPS_REGS_SPAN);
    hps_virtual_base = mmap(NULL, HPS_REGS_SPAN, PROT_READ | PROT_WRITE,
                            MAP_SHARED, fd, HPS_REGS_BASE);
    if (hps_virtual_base == MAP_FAILED) {
        perror("ERROR: mmap HPS regs failed");
        close(fd);
        return 1;
    }
    printf("  hps_virtual_base = %p\n", hps_virtual_base);

    printf("Memory mapping (LW bridge @ 0x%08X, span 0x%08X)...\n",
           (unsigned)LW_H2F_BASE, (unsigned)LW_BRIDGE_SPAN);
    lw_virtual_base = mmap(NULL, LW_BRIDGE_SPAN, PROT_READ | PROT_WRITE,
                           MAP_SHARED, fd, LW_H2F_BASE);
    if (lw_virtual_base == MAP_FAILED) {
        perror("ERROR: mmap LW bridge failed");
        cleanup();
        return 1;
    }
    printf("  lw_virtual_base  = %p\n", lw_virtual_base);

    // Validate offsets are inside the routed mm_bridge_0 window
    if (!lw_offset_in_range(BUTTON_PIO_BASE, "button_pio") ||
        !lw_offset_in_range(FSM_STATUS_PIO_BASE, "fsm_status_pio") ||
        !lw_offset_in_range(TIMER_STATUS_PIO_BASE, "timer_status_pio")) {
        cleanup();
        return 1;
    }

    // Map LW bridge register pointers (offsets are relative to LW base)
    button_addr       = (volatile uint32_t *)((uint8_t*)lw_virtual_base + BUTTON_PIO_BASE);
    fsm_status_addr   = (volatile uint32_t *)((uint8_t*)lw_virtual_base + FSM_STATUS_PIO_BASE);
    timer_status_addr = (volatile uint32_t *)((uint8_t*)lw_virtual_base + TIMER_STATUS_PIO_BASE);
    printf("  button_addr       = %p (LW + 0x%04X)\n", (void*)button_addr, (unsigned)BUTTON_PIO_BASE);
    printf("  fsm_status_addr   = %p (LW + 0x%04X)\n", (void*)fsm_status_addr, (unsigned)FSM_STATUS_PIO_BASE);
    printf("  timer_status_addr = %p (LW + 0x%04X)\n", (void*)timer_status_addr, (unsigned)TIMER_STATUS_PIO_BASE);

    // NOTE: A wrong/disabled bridge can hard-hang the CPU on the first MMIO read.
    // Keep this first access narrow and well-defined.
    uint32_t probe = *fsm_status_addr;
    if (probe == 0xFFFFFFFFu) {
        fprintf(stderr, "ERROR: fsm_status read returned 0xFFFFFFFF. "
                        "Is the FPGA programmed and LW bridge enabled?\n");
        cleanup();
        return 2;
    }

    printf("Initializing LCD...\n");
    LCDHW_Init(hps_virtual_base);
    LCD_Init();
    LCD_GraphicClear();
    LCDHW_BackLight(true);
    g_lcd_initialized = true;
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

            switch (hw_fsm_state) {
                case HW_FSM_INIT:
                case HW_FSM_IDLE:
                    if (!backlight_on) { LCDHW_BackLight(true); backlight_on = true; }
                    LCD_GraphicClear();
                    LCD_TextOut(0, 0,  "==================");
                    LCD_TextOut(0, 16, "  DE10-Standard   ");
                    LCD_TextOut(0, 32, "   LCD Message    ");
                    LCD_TextOut(0, 48, "  Press Any Key   ");
                    break;

                case HW_FSM_HOME:
                    if (!backlight_on) { LCDHW_BackLight(true); backlight_on = true; }
                    LCD_GraphicClear();
                    LCD_TextOut(0, 0,  "==================");
                    LCD_TextOut(0, 16, "  Welcome User!   ");
                    LCD_TextOut(0, 32, " KEY1/KEY2: Msgs  ");
                    LCD_TextOut(0, 48, " KEY0: Back       ");
                    break;

                case HW_FSM_MSG: {
                    int safe_idx = (hw_msg_index < MSG_COUNT) ? hw_msg_index : 0;
                    if (!backlight_on) { LCDHW_BackLight(true); backlight_on = true; }
                    LCD_GraphicClear();
                    LCD_TextOut(0, 0,  (char*)MSG_LIST[safe_idx][0]);
                    LCD_TextOut(0, 16, (char*)MSG_LIST[safe_idx][1]);
                    LCD_TextOut(0, 32, (char*)MSG_LIST[safe_idx][2]);
                    LCD_TextOut(0, 48, (char*)MSG_LIST[safe_idx][3]);
                    break;
                }

                case HW_FSM_SLEEP:
                    LCD_GraphicClear();
                    if (backlight_on) { LCDHW_BackLight(false); backlight_on = false; }
                    break;

                default:
                    if (!backlight_on) { LCDHW_BackLight(true); backlight_on = true; }
                    LCD_GraphicClear();
                    LCD_TextOut(0, 16, "  FSM ERROR STATE ");
                    // FIXED: latch the error so it doesn't redraw every loop
                    if (last_warn_code != 3) {
                        printf("[WARN] Unknown FSM state value=%d\n", hw_fsm_state);
                        last_warn_code = 3;
                    }
                    break;
            }

            last_hw_state     = hw_fsm_state;
            last_hw_msg_index = hw_msg_index;
        }

        usleep(5000);  // 5ms poll — meets latency budget after FPGA debounce reduction
    }

    cleanup();         // NEW: always release resources
    return 0;
}