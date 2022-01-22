/*
 * A simple shell with some basic features.
 *
 * Sami Samhuri 0327342
 * January 31, 2006
 * CSC 360, Assignment 1
 *
 * jobs.h
 * $Id: jobs.h 183 2006-01-27 11:24:52Z sjs $
 */

#include <stdlib.h>

struct job {
    int id;
    pid_t pid;
    char *cmdline;
    struct job *next;
    struct job *prev;
};
typedef struct job *job;

job add_job(pid_t pid, char **argv);
void delete_job(job j);
void free_job_list(void);
int get_num_jobs(void);
job get_job_list(void);
job job_with_id(int job_id);
job job_with_pid(pid_t pid);
