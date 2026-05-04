#include "render_screen.h"
#include "messages.h"

#ifdef UNIT_TEST
void LCD_TextOut(int x, int y, char *text);
void LCD_GraphicClear(void);
void LCDHW_BackLight(bool bON);
#else
#include "lcd_graphic.h"
#include "LCD_Hw.h"
#include "LCD_Lib.h"
#endif

enum {
    HW_FSM_INIT  = 0,
    HW_FSM_IDLE  = 1,
    HW_FSM_HOME  = 2,
    HW_FSM_MSG   = 3,
    HW_FSM_SLEEP = 4
};

bool render_screen(int hw_fsm_state, int hw_msg_index) {
    bool backlight_on = true;

    switch (hw_fsm_state) {
        case HW_FSM_INIT:
        case HW_FSM_IDLE:
            LCDHW_BackLight(true);
            LCD_GraphicClear();
            LCD_TextOut(0, 0,  "==================");
            LCD_TextOut(0, 16, "  DE10-Standard   ");
            LCD_TextOut(0, 32, "   LCD Message    ");
            LCD_TextOut(0, 48, "  Press Any Key   ");
            backlight_on = true;
            break;

        case HW_FSM_HOME:
            LCDHW_BackLight(true);
            LCD_GraphicClear();
            LCD_TextOut(0, 0,  "==================");
            LCD_TextOut(0, 16, "  Welcome User!   ");
            LCD_TextOut(0, 32, " KEY1/KEY2: Msgs  ");
            LCD_TextOut(0, 48, " KEY0: Back       ");
            backlight_on = true;
            break;

        case HW_FSM_MSG: {
            int safe_idx = (hw_msg_index < MSG_COUNT) ? hw_msg_index : 0;
            LCDHW_BackLight(true);
            LCD_GraphicClear();
            LCD_TextOut(0, 0,  (char*)MSG_LIST[safe_idx][0]);
            LCD_TextOut(0, 16, (char*)MSG_LIST[safe_idx][1]);
            LCD_TextOut(0, 32, (char*)MSG_LIST[safe_idx][2]);
            LCD_TextOut(0, 48, (char*)MSG_LIST[safe_idx][3]);
            backlight_on = true;
            break;
        }

        case HW_FSM_SLEEP:
            LCD_GraphicClear();
            LCDHW_BackLight(false);
            backlight_on = false;
            break;

        default:
            LCDHW_BackLight(true);
            LCD_GraphicClear();
            LCD_TextOut(0, 16, "  FSM ERROR STATE ");
            backlight_on = true;
            break;
    }

    return backlight_on;
}
