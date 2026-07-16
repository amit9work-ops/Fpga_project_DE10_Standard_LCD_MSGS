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
#include "soc_addr_map.h"

#define HPS_REGS_BASE         0xFC000000
#define HPS_REGS_SPAN         0x04000000

// Lightweight H2F base (fixed Cyclone V SoC physical address)
#define LW_H2F_BASE           0xFF200000

// From Platform Designer: mm_bridge_0.s0 window exposed to LW master
// 0x0000_0000 .. 0x0003_FFFF  => 0x0004_0000 bytes
#define LW_BRIDGE_SPAN        0x00040000

#define BUTTON_MASK           0x0F
#define TIMEOUT_SECONDS       60  // documentation only — actual system-idle
                                   // (sleep) timeout enforced in FPGA
                                   // (idle_timer.v), armed only while parked
                                   // in the DEFAULT category. The per-message
                                   // timer uses msg_duration_rom.v instead.
                                   // Not read here.

#define FSM_STATUS_STATE_SHIFT 5
#define FSM_STATUS_STATE_MASK  0xE0
#define FSM_STATUS_INDEX_MASK  0x1F

#define FSM_STATE_FROM_REG(v)  (((v) & FSM_STATUS_STATE_MASK) >> FSM_STATUS_STATE_SHIFT)
#define FSM_INDEX_FROM_REG(v)  ((v) & FSM_STATUS_INDEX_MASK)
#define MSG_COUNT              18

// Wide message-text interface: 16 x 32-bit words = 64 bytes = 4 lines x 16
// chars. status = {seq[2:0], text_index[4:0]}; the seqlock protocol is:
// read status -> read 16 words -> re-read status -> retry if it changed.
#define MSG_TEXT_WORDS          16
#define MSG_TEXT_LINES          4
#define MSG_TEXT_COLS           16
#define MSG_TEXT_STATUS_SEQ_MASK   0xE0
#define MSG_TEXT_STATUS_INDEX_MASK 0x1F
#define MSG_TEXT_SEQLOCK_MAX_RETRY 8

// round 2: 3-state FSM (INIT/MSG/SLEEP), replacing round 1's 5-state
// (INIT/IDLE/HOME/MSG/SLEEP). Encoding must match message_fsm.v.
typedef enum {
    HW_FSM_INIT  = 0,
    HW_FSM_MSG   = 1,
    HW_FSM_SLEEP = 2
} HwFsmState;

// === Globals ===
static void *hps_virtual_base = MAP_FAILED;
static void *lw_virtual_base  = MAP_FAILED;
static volatile uint32_t *button_addr       = NULL;
static volatile uint32_t *fsm_status_addr   = NULL;
static volatile uint32_t *timer_status_addr = NULL;
static volatile uint32_t *msg_text_addr[MSG_TEXT_WORDS];
static volatile uint32_t *msg_text_status_addr = NULL;
static int  fd = -1;
static bool g_lcd_initialized = false;

// NEW: graceful shutdown flag (signal-safe)
static volatile sig_atomic_t g_shutdown = 0;

static const char* hw_fsm_state_name(int state) {
    switch (state) {
        case HW_FSM_INIT:  return "INIT";
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

// Reads the current message text via the seqlock protocol: read status,
// read all 16 words, re-read status, retry if the sequence changed mid-read
// (the FPGA advanced to a new message while we were reading the old one).
// On success, fills out_bytes[64] (byte B=line*16+col) and *out_index with
// the index the returned text actually belongs to (the authority for what
// is on screen — not fsm_status_pio's index, which can update one FPGA
// clock cycle before the text snapshot does).
static bool read_msg_text(uint8_t out_bytes[MSG_TEXT_LINES * MSG_TEXT_COLS], int *out_index) {
    for (int retry = 0; retry < MSG_TEXT_SEQLOCK_MAX_RETRY; retry++) {
        uint32_t s0 = *msg_text_status_addr;
        uint32_t words[MSG_TEXT_WORDS];
        for (int w = 0; w < MSG_TEXT_WORDS; w++) {
            words[w] = *msg_text_addr[w];
        }
        uint32_t s1 = *msg_text_status_addr;

        if (s0 == s1) {
            for (int b = 0; b < MSG_TEXT_LINES * MSG_TEXT_COLS; b++) {
                out_bytes[b] = (uint8_t)((words[b / 4] >> (8 * (b % 4))) & 0xFF);
            }
            if (out_index) {
                *out_index = (int)(s0 & MSG_TEXT_STATUS_INDEX_MASK);
            }
            return true;
        }
        // Torn read: the index changed mid-read. Retry with the new snapshot.
    }
    return false;
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
    static const uint32_t msg_text_base[MSG_TEXT_WORDS] = {
        MSG_TEXT_PIO_0_BASE,  MSG_TEXT_PIO_1_BASE,  MSG_TEXT_PIO_2_BASE,  MSG_TEXT_PIO_3_BASE,
        MSG_TEXT_PIO_4_BASE,  MSG_TEXT_PIO_5_BASE,  MSG_TEXT_PIO_6_BASE,  MSG_TEXT_PIO_7_BASE,
        MSG_TEXT_PIO_8_BASE,  MSG_TEXT_PIO_9_BASE,  MSG_TEXT_PIO_10_BASE, MSG_TEXT_PIO_11_BASE,
        MSG_TEXT_PIO_12_BASE, MSG_TEXT_PIO_13_BASE, MSG_TEXT_PIO_14_BASE, MSG_TEXT_PIO_15_BASE,
    };

    if (!lw_offset_in_range(BUTTON_PIO_BASE, "button_pio") ||
        !lw_offset_in_range(FSM_STATUS_PIO_BASE, "fsm_status_pio") ||
        !lw_offset_in_range(TIMER_STATUS_PIO_BASE, "timer_status_pio") ||
        !lw_offset_in_range(MSG_TEXT_STATUS_PIO_BASE, "msg_text_status_pio")) {
        cleanup();
        return 1;
    }
    for (int w = 0; w < MSG_TEXT_WORDS; w++) {
        char name[32];
        snprintf(name, sizeof(name), "msg_text_pio_%d", w);
        if (!lw_offset_in_range(msg_text_base[w], name)) {
            cleanup();
            return 1;
        }
    }

    // Map LW bridge register pointers (offsets are relative to LW base)
    button_addr            = (volatile uint32_t *)((uint8_t*)lw_virtual_base + BUTTON_PIO_BASE);
    fsm_status_addr        = (volatile uint32_t *)((uint8_t*)lw_virtual_base + FSM_STATUS_PIO_BASE);
    timer_status_addr      = (volatile uint32_t *)((uint8_t*)lw_virtual_base + TIMER_STATUS_PIO_BASE);
    msg_text_status_addr   = (volatile uint32_t *)((uint8_t*)lw_virtual_base + MSG_TEXT_STATUS_PIO_BASE);
    for (int w = 0; w < MSG_TEXT_WORDS; w++) {
        msg_text_addr[w] = (volatile uint32_t *)((uint8_t*)lw_virtual_base + msg_text_base[w]);
    }
    printf("  button_addr       = %p (LW + 0x%04X)\n", (void*)button_addr, (unsigned)BUTTON_PIO_BASE);
    printf("  fsm_status_addr   = %p (LW + 0x%04X)\n", (void*)fsm_status_addr, (unsigned)FSM_STATUS_PIO_BASE);
    printf("  timer_status_addr = %p (LW + 0x%04X)\n", (void*)timer_status_addr, (unsigned)TIMER_STATUS_PIO_BASE);
    printf("  msg_text_status   = %p (LW + 0x%04X)\n", (void*)msg_text_status_addr, (unsigned)MSG_TEXT_STATUS_PIO_BASE);

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

    int  last_hw_state      = -1;
    int  last_text_index    = -1;
    bool backlight_on       = true;
    int  last_warn_code     = 0;
    int  text_fail_streak   = 0;

    printf("\n=== LCD MESSAGE SYSTEM STARTED ===\n");
    printf("Using FPGA hardware debouncing, navigation, and message text.\n");
    printf("Press Ctrl+C to exit cleanly.\n\n");

    // === MAIN LOOP ===
    while (!g_shutdown) {                          // CHANGED: was while(1)
        uint32_t fsm_status   = *fsm_status_addr;
        uint32_t timer_status = *timer_status_addr;

        int  hw_fsm_state = FSM_STATE_FROM_REG(fsm_status);
        bool timeout       = timer_status & 1;
        int  secs_left     = (timer_status >> 1) & 0x3F;  // bits[6:1], 0-63

        // The message text and its index are read together via the seqlock;
        // text_index (not fsm_status's index) is the authority for what is
        // actually on screen right now.
        uint8_t text_bytes[MSG_TEXT_LINES * MSG_TEXT_COLS];
        int text_index = -1;
        bool have_text = read_msg_text(text_bytes, &text_index);
        if (!have_text) {
            text_fail_streak++;
            if (text_fail_streak == 1 || text_fail_streak % 200 == 0) {
                fprintf(stderr, "[WARN] msg text seqlock read failed %d time(s) in a row "
                                "(persistent tearing?)\n", text_fail_streak);
            }
        } else {
            text_fail_streak = 0;
        }

        bool state_changed = (hw_fsm_state != last_hw_state);
        bool text_changed  = have_text && (text_index != last_text_index);

        if (state_changed && hw_fsm_state == HW_FSM_MSG &&
            have_text && (text_index < 0 || text_index >= MSG_COUNT)) {
            if (last_warn_code != 2) {
                printf("[WARN] FSM=MSG with out-of-range text_index=%d\n", text_index);
                last_warn_code = 2;
            }
        } else if (!state_changed) {
            last_warn_code = 0;
        }

        if (state_changed || text_changed) {
            printf("HW FSM: %s(%d), text_idx=%d, secs_left=%d, timeout=%d\n",
                   hw_fsm_state_name(hw_fsm_state), hw_fsm_state,
                   text_index, secs_left, timeout ? 1 : 0);

            switch (hw_fsm_state) {
                case HW_FSM_INIT:
                    // Transient: the FPGA moves INIT->MSG within one clock
                    // cycle of reset release, so the HPS should rarely if
                    // ever observe this. Defensive placeholder only.
                    if (!backlight_on) { LCDHW_BackLight(true); backlight_on = true; }
                    LCD_GraphicClear();
                    LCD_TextOut(0, 0,  "================");
                    LCD_TextOut(0, 16, " DE10-Standard  ");
                    LCD_TextOut(0, 32, "  LCD Message   ");
                    LCD_TextOut(0, 48, "   Starting...  ");
                    break;

                case HW_FSM_MSG: {
                    if (!backlight_on) { LCDHW_BackLight(true); backlight_on = true; }
                    if (have_text) {
                        char line[MSG_TEXT_COLS + 1];
                        LCD_GraphicClear();
                        for (int l = 0; l < MSG_TEXT_LINES; l++) {
                            memcpy(line, &text_bytes[l * MSG_TEXT_COLS], MSG_TEXT_COLS);
                            line[MSG_TEXT_COLS] = '\0';
                            LCD_TextOut(0, l * 16, line);
                        }
                    }
                    // If !have_text (persistent tearing), keep whatever was
                    // last drawn rather than blank the screen or show
                    // corrupted text.
                    break;
                }

                case HW_FSM_SLEEP:
                    LCD_GraphicClear();
                    if (backlight_on) { LCDHW_BackLight(false); backlight_on = false; }
                    break;

                default:
                    if (!backlight_on) { LCDHW_BackLight(true); backlight_on = true; }
                    LCD_GraphicClear();
                    LCD_TextOut(0, 16, " FSM ERROR STATE");
                    // FIXED: latch the error so it doesn't redraw every loop
                    if (last_warn_code != 3) {
                        printf("[WARN] Unknown FSM state value=%d\n", hw_fsm_state);
                        last_warn_code = 3;
                    }
                    break;
            }

            last_hw_state   = hw_fsm_state;
            if (have_text) {
                last_text_index = text_index;
            }
        }

        usleep(5000);  // 5ms poll — meets latency budget after FPGA debounce reduction
    }

    cleanup();         // NEW: always release resources
    return 0;
}
