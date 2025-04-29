#ifndef GET_INPUT_H
#define GET_INPUT_H

#define SHIFT_KEY_MODIFIER 0b1
#define CTRL_KEY_MODIFIER 0b10
#define ALT_KEY_MODIFIER 0b100
#define ARROW_KEY_MODIFIER 0b1000
#define FUNCTION_KEY_MODIFIER 0b10000
#define ENTER_KEY_MODIFIER 0b100000
#define ESCAPE_KEY_MODIFIER 0b1000000

typedef struct {
    unsigned int keyCode; // Key code
    unsigned int modifiers; // Bit mask for modifiers
} Key;

void set_input_callback(void (*callback)(Key key));
void enable_raw_mode();
void disable_raw_mode();
Key get_input();


#endif