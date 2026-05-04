#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>

#include "mock_lcd.h"
#include "messages.h"

#define FSM_STATUS_STATE_SHIFT 5
#define FSM_STATE_FROM_REG(v) (((v)&0xE0)>>5)
#define FSM_INDEX_FROM_REG(v) ((v)&0x1F)

bool render_screen(int hw_fsm_state, int hw_msg_index);

static int tests_run = 0;
static int tests_passed = 0;

static void run_test(const char *name, int (*fn)(void)) {
    mock_lcd_reset();
    tests_run++;
    int ok = fn();
    if (ok) {
        printf("[ PASS ] %s\n", name);
        tests_passed++;
    } else {
        printf("[ FAIL ] %s\n", name);
    }
}

static int test_t01(void) {
    bool backlight = render_screen(0, 0);
    return backlight &&
           mock_lcd_has_text("DE10") &&
           mock_lcd_has_text("Press Any Key") &&
           g_mock_lcd.backlight_state == true;
}

static int test_t02(void) {
    bool backlight = render_screen(1, 0);
    return backlight &&
           mock_lcd_has_text("DE10") &&
           mock_lcd_has_text("Press Any Key") &&
           g_mock_lcd.backlight_state == true;
}

static int test_t03(void) {
    bool backlight = render_screen(2, 0);
    return backlight &&
           mock_lcd_has_text("Welcome User") &&
           mock_lcd_has_text("KEY1/KEY2") &&
           mock_lcd_has_text("KEY0: Back") &&
           g_mock_lcd.backlight_state == true;
}

static int test_t04(void) {
    bool backlight = render_screen(3, 0);
    return backlight &&
           g_mock_lcd.line_count == 4 &&
           mock_lcd_has_text(MSG_LIST[0][0]);
}

static int test_t05(void) {
    render_screen(3, 17);
    return mock_lcd_has_text(MSG_LIST[17][0]);
}

static int test_t06(void) {
    bool backlight = render_screen(4, 0);
    return !backlight &&
           g_mock_lcd.backlight_state == false &&
           g_mock_lcd.clear_calls >= 1;
}

static int test_t07(void) {
    bool backlight = render_screen(5, 0);
    return backlight &&
           mock_lcd_has_text("FSM ERROR") &&
           g_mock_lcd.backlight_state == true;
}

static int test_t08(void) {
    bool backlight = render_screen(0xFF, 0);
    return backlight &&
           mock_lcd_has_text("FSM ERROR") &&
           g_mock_lcd.backlight_state == true;
}

static int test_t09(void) {
    render_screen(3, 18);
    return mock_lcd_has_text(MSG_LIST[0][0]);
}

static int test_t10(void) {
    render_screen(3, 99);
    return mock_lcd_has_text(MSG_LIST[0][0]);
}

static int test_t11(void) {
    uint32_t reg = (3u << 5) | 7u;
    int state = FSM_STATE_FROM_REG(reg);
    int idx = FSM_INDEX_FROM_REG(reg);
    if (state != 3 || idx != 7) {
        return 0;
    }
    render_screen(state, idx);
    return mock_lcd_has_text(MSG_LIST[7][0]);
}

static int test_t12(void) {
    render_screen(4, 0);
    bool s_off = !g_mock_lcd.backlight_state;
    render_screen(2, 0);
    bool s_on = g_mock_lcd.backlight_state;
    return s_off && s_on;
}

int main(void) {
    printf("=== HPS Renderer Self-Check ===\n");
    run_test("T01_INIT_splash",          test_t01);
    run_test("T02_IDLE_splash",          test_t02);
    run_test("T03_HOME_menu",            test_t03);
    run_test("T04_MSG_index_0",          test_t04);
    run_test("T05_MSG_index_17",         test_t05);
    run_test("T06_SLEEP_backlight_off",  test_t06);
    run_test("T07_invalid_state_5",      test_t07);
    run_test("T08_invalid_state_0xFF",   test_t08);
    run_test("T09_msg_index_18_clamp",   test_t09);
    run_test("T10_msg_index_99_clamp",   test_t10);
    run_test("T11_register_decode",      test_t11);
    run_test("T12_backlight_transition", test_t12);
    printf("=== Result: %d / %d ===\n", tests_passed, tests_run);
    return (tests_passed == tests_run) ? 0 : 1;
}
