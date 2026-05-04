#ifndef RENDER_SCREEN_H
#define RENDER_SCREEN_H

#ifdef __cplusplus
extern "C" {
#endif

/* MSG_COUNT must be visible to render_screen.c via messages.h */

/* render_screen()
 * Renders the LCD screen that corresponds to the given hardware
 * FSM state. Uses LCD_GraphicClear, LCD_TextOut, and
 * LCDHW_BackLight. Safe against invalid state and invalid
 * msg_index values.
 *
 * Returns the backlight target state after rendering:
 *   true  = backlight ON
 *   false = backlight OFF
 */
#include <stdbool.h>
bool render_screen(int hw_fsm_state, int hw_msg_index);

#ifdef __cplusplus
}
#endif
#endif /* RENDER_SCREEN_H */
