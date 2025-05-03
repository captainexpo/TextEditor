#include "regez.h"


void regex_replace(const char *pattern, const char *replace, const char *input, char *output, size_t maxlen) {
    regex_t regex;
    regmatch_t match;

    if (regcomp(&regex, pattern, REG_EXTENDED)) {
        fprintf(stderr, "Regex compilation failed\n");
        return;
    }

    if (!regexec(&regex, input, 1, &match, 0)) {
        size_t before_len = match.rm_so;
        size_t after_len = strlen(input) - match.rm_eo;

        snprintf(output, maxlen, "%.*s%s%s",
                 (int)before_len,
                 input,
                 replace,
                 input + match.rm_eo);
    } else {
        strncpy(output, input, maxlen); // No match, copy original
    }

    regfree(&regex);
}
