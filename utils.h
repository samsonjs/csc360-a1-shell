/*
 * A simple shell with some basic features.
 *
 * Sami Samhuri 0327342
 * January 31, 2006
 * CSC 360, Assignment 1
 *
 * utils.h
 * $Id: utils.h 184 2006-01-29 08:53:30Z sjs $
 */
 
#include <stdlib.h>

#define DEBUG	1
#define MSGLEN	255			/* soft limit on message lengths */

/* these colours should be safe on dark and light backgrounds */
#define BLUE	"\033[1;34m"
#define GREEN	"\033[1;32m"
#define YELLOW	"\033[1;33m"
#define RED		"\033[1;31m"
#define WHITE	"\033[1;37m"
#define CLEAR	"\033[0;m"

/* free an array/list's elements (then the array itself) */
void free_array ( void **array );

/* concatenate an array of strings, adding space between words */
char *array_cat ( char **array );

/* safe malloc & realloc, they exit on failure */
void *myxmalloc	( size_t size );
void *myxrealloc	( void *ptr, size_t size );

#define xfree(ptr) if (ptr) free (ptr);

/* this takes n_elems of the original array, in case of failure it will
 * free_array (n_elems, array) before exiting */
void **array_realloc ( void **array, size_t size );
