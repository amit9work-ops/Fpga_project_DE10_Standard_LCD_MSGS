#include "mock_lcd.h"

#include <string.h>

mock_lcd_state_t g_mock_lcd;

void LCD_TextOut(int x, int y, char *text) {
    g_mock_lcd.textout_calls++;
    if (g_mock_lcd.line_count < MOCK_MAX_LINES) {
        int idx = g_mock_lcd.line_count;
        g_mock_lcd.line_x[idx] = x;
        g_mock_lcd.line_y[idx] = y;
        if (text != NULL) {
            strncpy(g_mock_lcd.lines[idx], text, MOCK_MAX_LINE_LEN - 1);
            g_mock_lcd.lines[idx][MOCK_MAX_LINE_LEN - 1] = '\0';
        } else {
            g_mock_lcd.lines[idx][0] = '\0';
        }
        g_mock_lcd.line_count++;
    }
}

void LCD_GraphicClear(void) {
    g_mock_lcd.clear_calls++;
    g_mock_lcd.line_count = 0;
}

void LCDHW_BackLight(bool bON) {
    g_mock_lcd.backlight_calls++;
    g_mock_lcd.backlight_state = bON;
}

void LCDHW_Init(void *virtual_base) {
    (void)virtual_base;
    g_mock_lcd.init_hw_calls++;
}

void LCD_Init(void) {
    g_mock_lcd.init_lcd_calls++;
}

void mock_lcd_reset(void) {
    memset(&g_mock_lcd, 0, sizeof(g_mock_lcd));
}

bool mock_lcd_has_text(const char *needle) {
    int i;

    if (needle == NULL) {
        return false;
    }

    for (i = 0; i < g_mock_lcd.line_count; i++) {
        if (strstr(g_mock_lcd.lines[i], needle) != NULL) {
            return true;
        }
    }

    return false;
}

int mock_lcd_text_at(int x, int y, const char *needle) {
    int i;

    if (needle == NULL) {
        return 0;
    }

    for (i = 0; i < g_mock_lcd.line_count; i++) {
        if (g_mock_lcd.line_x[i] == x && g_mock_lcd.line_y[i] == y) {
            if (strstr(g_mock_lcd.lines[i], needle) != NULL) {
                return 1;
            }
        }
    }

    return 0;
}
