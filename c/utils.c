/*
 * A simple shell with some basic features.
 *
 * Sami Samhuri 0327342
 * January 31, 2006
 * CSC 360, Assignment 1
 *
 * utils.c
 * $Id: utils.c 184 2006-01-29 08:53:30Z sjs $
 */

#include "utils.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char *array_cat(char **array) {
    char *p = NULL, *str = NULL;
    int i, pos = 0;
    for (i = 0; array[i]; i++) {
        int len = strlen(array[i]);
        str = (char *)myxrealloc(str, pos + len + 1);
        p = str + pos;
        memcpy(p, array[i], len);
        p += len;
        *p++ = ' ';
        pos += len + 1;
    }
    *--p = '\0';
    return str;
}

void free_array(void **array) {
    int i = 0;

    if (!array)
        return;

    while (array[i])
        free(array[i++]);
    free(array);
}

void *myxmalloc(size_t size) {
    void *ptr = malloc(size);
    if (ptr)
        return ptr;

    printf(RED "Out of memory, bailing!\n" CLEAR);
    exit(EXIT_FAILURE);
}

void *myxrealloc(void *ptr, size_t size) {
    void *new_ptr = realloc(ptr, size);
    if (new_ptr)
        return new_ptr;

    printf(RED "Out of memory, bailing!\n" CLEAR);
    exit(EXIT_FAILURE);
}

void **array_realloc(void **array, size_t size) {
    void **ptr = realloc(array, size * sizeof(void *));
    if (ptr)
        return ptr;

    free_array(array);
    printf(RED "Out of memory, bailing!\n" CLEAR);
    exit(EXIT_FAILURE);
}
