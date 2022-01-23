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
#include "utils.h"

int builtin_bg(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "bg: usage 'bg <command>'\n");
        fprintf(stderr, "    runs <command> in the background\n");
        return -1;
    }

    pid_t pid = exec_command(&argv[1], 1); /* &argv[1] skips 'bg' */
    if (pid > 0) {
        job j = add_job(pid, &argv[1]);
        printf("Running job " YELLOW "%i" WHITE " (pid %i) in background\n" CLEAR, j->id, pid);
    }
    return pid;
}

int builtin_bgkill(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "bgkill: usage 'bgkill <job number>'\n");
        fprintf(stderr, "        type 'bglist' to see running jobs=n");
        return -1;
    }

    int job_id = atoi(argv[1]);
    job j = job_with_id(job_id);
    if (!j) {
        fprintf(stderr, YELLOW "Invalid job number\n");
        fprintf(stderr, "(type 'bglist' to see running jobs)\n");
        return -1;
    }

    kill(j->pid, SIGTERM);
    return 1;
}

int builtin_bglist(void) {
    int num_jobs;
    if (!(num_jobs = get_num_jobs()))
        return 0;

    job j;
    for (j = get_job_list(); j; j = j->next) {
        printf(YELLOW "%i" WHITE ": (pid %i)" YELLOW " %s\n" CLEAR, j->id, j->pid, j->cmdline);
    }
    printf(GREEN "Total: %i background job(s) running\n" CLEAR, num_jobs);
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
        fprintf(stderr, RED "cd: %s: %s" CLEAR, strerror(errno), dir);
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
