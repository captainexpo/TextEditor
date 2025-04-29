#include "get_input.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <termios.h>
#include <fcntl.h>
#include <sys/select.h>
#include <signal.h>


// Save original terminal state
static struct termios original_termios;

// Input callback
static void (*input_callback)(Key key) = NULL;

void set_input_callback(void (*callback)(Key key)) {
    input_callback = callback;
}

// Set raw mode
void enable_raw_mode() {
    tcgetattr(STDIN_FILENO, &original_termios);

    struct termios raw = original_termios;
    raw.c_lflag &= ~(ICANON | ECHO | ISIG); // Disable canonical mode, echo, and signals (like Ctrl+C)
    raw.c_iflag &= ~(IXON | ICRNL);          // Disable Ctrl-S/Q and carriage return translation
    tcsetattr(STDIN_FILENO, TCSANOW, &raw);
}

// Restore terminal to original state
void disable_raw_mode() {
    tcsetattr(STDIN_FILENO, TCSANOW, &original_termios);
}

Key get_input() {
    Key key = {0, 0};
    char c;

    // Blocking read for 1 byte
    read(STDIN_FILENO, &c, 1);

    if (c == '\033') { // ESC detected
        struct timeval tv = {0, 50000}; // 50ms timeout
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(STDIN_FILENO, &fds);

        int ret = select(STDIN_FILENO + 1, &fds, NULL, NULL, &tv);
        if (ret > 0) {
            // More input after ESC
            char next;
            read(STDIN_FILENO, &next, 1);
            if (next == '[') {
                char seq;
                if (read(STDIN_FILENO, &seq, 1) > 0) {
                    switch (seq) {
                        case 'A': key.keyCode = 65; key.modifiers = ARROW_KEY_MODIFIER; break; // Up
                        case 'B': key.keyCode = 66; key.modifiers = ARROW_KEY_MODIFIER; break; // Down
                        case 'C': key.keyCode = 67; key.modifiers = ARROW_KEY_MODIFIER; break; // Right
                        case 'D': key.keyCode = 68; key.modifiers = ARROW_KEY_MODIFIER; break; // Left
                    }
                }
            } else {
                // Alt + key
                key.keyCode = next;
                key.modifiers = ALT_KEY_MODIFIER;
            }
        } else {
            printf("ESC key pressed\n");
            // Just an ESC key
            key.keyCode = 27;
            key.modifiers = ESCAPE_KEY_MODIFIER; // Added ESC key modifier
        }
    } else if (c == '\n' || c == '\r') {
        // Enter key
        key.keyCode = '\n';
        key.modifiers = ENTER_KEY_MODIFIER;
    } else {
        key.keyCode = (unsigned char)c;

        if (c >= 1 && c <= 26) {
            // Ctrl+A to Ctrl+Z
            key.keyCode = c + 'A' - 1;
            key.modifiers = CTRL_KEY_MODIFIER;
        } else if (c >= 'A' && c <= 'Z') {
            // Shifted capital letter
            key.modifiers = SHIFT_KEY_MODIFIER;
        } else {
            key.modifiers = 0;
        }
    }

    if (input_callback) {
        input_callback(key);
    }

    return key;
}

#ifdef DEBUG

void print_binary(unsigned int num) {
    if (num >> 1) {
        print_binary(num >> 1);
    }
    putchar((num & 1) ? '1' : '0');
}

void example_callback(Key key) {
    if (key.keyCode == 27) {
        printf("ESC key pressed\n");
        exit(0);
    }
    printf("Key pressed: %c, Modifiers: ", key.keyCode);
    print_binary(key.modifiers);
    printf("\n");
}

int main() {
    // Ignore Ctrl+C
    signal(SIGINT, SIG_IGN);

    // Enable raw mode
    enable_raw_mode();

    // Make sure terminal gets restored on exit
    atexit(disable_raw_mode);

    set_input_callback(example_callback);
    printf("Press any key (ESC to exit):\n");

    while (1) {
        get_input();
    }

    return 0;
}

#endif