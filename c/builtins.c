/*
 * A simple shell with some basic features.
 *
 * Sami Samhuri 0327342
 * January 31, 2006
 * CSC 360, Assignment 1
 *
 * builtins.c
 * $Id: builtins.c 184 2006-01-29 08:53:30Z sjs $
 */

/*#define _GNU_SOURCE*/

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#include "builtins.h"
#include "exec.h"
#include "jobs.h"
#include "main.h"
#include "utils.h"

int builtin_bg(int argc, char **argv) {
    if (argc < 2) {
        queue_message("bg: usage 'bg <command>'");
        queue_message("    runs <command> in the background");
        return -1;
    }

    pid_t pid = exec_command(&argv[1], 1); /* &argv[1] skips 'bg' */
    if (pid > 0) {
        job j = add_job(pid, &argv[1]);

        char *message = (char *)myxmalloc(MSGLEN);
        snprintf(message, MSGLEN, "Running job " YELLOW "%i" WHITE " (pid %i) in background" CLEAR, j->id, pid);
        queue_message(message);
        free(message);
    }
    return pid;
}

int builtin_bgkill(int argc, char **argv) {
    if (argc != 2) {
        queue_message("bgkill: usage 'bgkill <job number>'");
        queue_message("        type 'bglist' to see running jobs");
        return -1;
    }

    int job_id = atoi(argv[1]);
    job j = job_with_id(job_id);
    if (!j) {
        queue_message(YELLOW "Invalid job number");
        queue_message("(type 'bglist' to see running jobs)");
        return -1;
    }

    kill(j->pid, SIGTERM);
    /*delete_job (j);*/
    /*	queue_message ("Job killed");*/
    return 1;
}

int builtin_bglist(void) {
    int num_jobs;
    if (!(num_jobs = get_num_jobs()))
        return 0;

    job j;
    char *message = (char *)myxmalloc(MSGLEN);
    for (j = get_job_list(); j; j = j->next) {
        snprintf(message, MSGLEN, YELLOW "%i" WHITE ": (pid %i)" YELLOW " %s" CLEAR, j->id, j->pid, j->cmdline);
        queue_message(message);
    }
    snprintf(message, MSGLEN, GREEN "Total: %i background job(s) running" CLEAR, num_jobs);
    queue_message(message);
    free(message);
    return num_jobs;
}

int builtin_cd(int argc, char **argv) {
    static char *lastdir = NULL;
    char *dir, *pwd = getcwd(NULL, 0);

    if (!lastdir) /* initialize */
        lastdir = pwd;

    if (argc < 2) /* cd w/ no args acts like cd $HOME */
        dir = getenv("HOME");
    else {
        if (!strncmp(argv[1], "-", 1))
            dir = lastdir; /* cd - changes to previous dir */
        else
            dir = argv[1];
    }

    if (chdir(dir) < 0) { /* error */
        size_t len = strlen(dir);
        char *message = (char *)myxmalloc(len + MSGLEN);
        (void)snprintf(message, len + MSGLEN, RED "cd: %s: %s" CLEAR, strerror(errno), dir);
        queue_message(message);
        free(message);
        return -1;
    }

    /* save the last dir for cd -, if it's different */
    if (strcmp(pwd, dir))
        lastdir = pwd;
    return 1;
}

void builtin_clear(void) { printf("\033[2J"); }

void builtin_pwd(void) {
    char *pwd = getcwd(NULL, 0);
    printf("%s\n", pwd);
    xfree(pwd);
}
