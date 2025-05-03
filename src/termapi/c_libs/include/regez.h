#ifndef REGEX_H
#define REGEX_H

#include <string.h>
#include <stdio.h>
#include <regex.h>
#include <stdalign.h>

void regex_replace(const char *pattern, const char *replace, const char *input, char *output, size_t maxlen);

#endif
