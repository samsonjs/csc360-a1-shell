/*
 * A simple shell with some basic features.
 *
 * Sami Samhuri 0327342
 * January 31, 2006
 * CSC 360, Assignment 1
 *
 * exec.c -- fork and execute a program
 * $Id: exec.c 184 2006-01-29 08:53:30Z sjs $
 */

/*#define _GNU_SOURCE*/

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h> /* waitpid */
#include <sys/wait.h>  /* waitpid */
#include <unistd.h>

#include "exec.h"
#include "main.h"
#include "utils.h"

char *is_executable(char *file) {
    if (strchr(file, '/')) { /* process absolute and relative paths directly */
        if (access(file, X_OK) == 0)
            return strdup(file);
        else
            return NULL;
    }

    char *path = strdup(getenv("PATH"));
    int file_len = strlen(file);
    char *dir = strtok(path, ":");
    char *filename = NULL;
    while (dir) {
        filename = (char *)myxmalloc(strlen(dir) + file_len + 2);
        sprintf(filename, "%s/%s", dir, file);
        if (access(filename, X_OK) == 0)
            break;
        free(filename);
        filename = NULL;
        dir = strtok(NULL, ":");
    }
    xfree(path);
    return filename;
}

pid_t exec_command(char **argv, int background) {
    int status;
    pid_t pid;
    char *filename;

    if (!(filename = is_executable(argv[0]))) { /* error, not executable */
        char *msg = (char *)myxmalloc(MSGLEN);
        sprintf(msg, RED "%s: %s" CLEAR, argv[0], strerror(errno));
        queue_message(msg);
        free(msg);
        return -1;
    }

    if ((pid = fork()) > 0) { /* parent */
        if (background)
            waitpid(pid, &status, WNOHANG);
        else
            waitpid(pid, &status, 0);
    } else if (pid == 0) { /* child */
        /* kludge, briefly wait for the job to be created so that if the
         * command exits quickly, the job is found and removed. otherwise there
         * are zombie jobs erroneously lying around. note, this isn't guaranteed
         * to work, it just seems to be enough time in tests here.
         */
        usleep(100);
        execv(filename, argv);

        /* if we get here there was an error, display it */
        printf(RED "\nCannot execute '%s' (%s)\n" CLEAR, argv[0], strerror(errno));
        free(filename);
        _exit(EXIT_FAILURE);
    } else { /* error, pid < 0 */
        queue_message(RED "Unable to fork(), uh oh..." CLEAR);
    }
    free(filename);
    return pid;
}
