#ifndef MOCK_LCD_H
#define MOCK_LCD_H

#include <stdbool.h>

#define MOCK_MAX_LINES 8
#define MOCK_MAX_LINE_LEN 64

typedef struct {
    int  clear_calls;
    int  textout_calls;
    int  backlight_calls;
    bool backlight_state;
    int  init_lcd_calls;
    int  init_hw_calls;

    char lines[MOCK_MAX_LINES][MOCK_MAX_LINE_LEN];
    int  line_x[MOCK_MAX_LINES];
    int  line_y[MOCK_MAX_LINES];
    int  line_count;
} mock_lcd_state_t;

extern mock_lcd_state_t g_mock_lcd;

void mock_lcd_reset(void);
bool mock_lcd_has_text(const char *needle);
int  mock_lcd_text_at(int x, int y, const char *needle);

#endif
