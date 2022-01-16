/*
 * A simple shell with some basic features.
 *
 * Sami Samhuri 0327342
 * January 31, 2006
 * CSC 360, Assignment 1
 *
 * jobs.c
 * $Id: jobs.c 184 2006-01-29 08:53:30Z sjs $
 */

/*#define _GNU_SOURCE*/
 
#include <stdio.h>
#include <string.h>

#include "jobs.h"
#include "main.h"
#include "utils.h"

#define MIN(a, b) ((a) < (b)) ? (a) : (b)

static job job_list_head = NULL;
static int num_jobs = 0;
static int next_id = 1;

static int get_next_id ( void )
{
	while ( job_with_id (next_id) )
		next_id++;
	return next_id++;
}

job add_job ( pid_t pid, char **argv )
{
	job i, j = (job)myxmalloc (sizeof (struct job));
	j->id = get_next_id();
	j->pid = pid;
	j->cmdline = array_cat (argv);
	if (DEBUG)
		printf("DEBUG: cmdline='%s'\n", j->cmdline);
	j->next = NULL;
	j->prev = NULL;

	for (i = job_list_head; i && i->next; i = i->next)
	{	/* insert jobs in job_id order */
		if ( i->id > j->id )
		{	/* insert BEFORE i */
			if (DEBUG)
				printf("DEBUG: i=%i, i->next=%i, i->prev=%p\n", i->id, i->next->id, i->prev);
			j->next = i;
			j->prev = i->prev;
			if (i->prev)
				i->prev->next = j;
			i->prev = j;

			if ( job_list_head == i )
				job_list_head = j;
			break;
		}
	}

	if ( i == NULL )	/* empty list */
	{
		if (DEBUG)
			printf("DEBUG: i=%p, job_list_head=%p\n", i, job_list_head);
		job_list_head = j;
	}
	else if ( !i->next )	/* at the end, i->next == NULL */
	{	/* at this point, append the new job to the end of the list */
		if (DEBUG)
			printf("DEBUG: i=%i\n", i->id);
		i->next = j;
		j->prev = i;
	}
	if (DEBUG)
		printf("DEBUG: job added: (%i,%i)\n", j->id, j->pid);
	num_jobs++;
	return j;
}

void delete_job ( job j )
{
	next_id = MIN(next_id, j->id);				/* prefer the lower id */

	if ( j == job_list_head )
	{
		if (j->next)
			job_list_head = j->next;
		else
			job_list_head = NULL;
	}
	if (j->prev)
		j->prev->next = j->next;
	if (j->next)
		j->next->prev = j->prev;

	if (DEBUG)
		printf("DEBUG: str=%p\n", j->cmdline);
	xfree (j->cmdline);
	xfree (j);
	num_jobs--;
}

void free_job_list ( void )
{
	while ( job_list_head )
		delete_job ( job_list_head );
}

job job_with_id ( int job_id )
{
	job j;
	for (j = job_list_head; j; j = j->next)
	{
/*		printf("DEBUG: id=%i, j=%p:%i:%i\n", job_id, j, j->id, j->pid); */
		if (j->id == job_id)
			return j;
	}
	return NULL;
}

job job_with_pid ( pid_t pid )
{
	job j;
	for (j = job_list_head; j; j = j->next)
	{
		printf("DEBUG: pid=%i, j=%p:%i:%i\n", pid, j, j->id, j->pid);
		if (j->pid == pid)
			return j;
	}
	return NULL;
}

job get_job_list ( void )
{
	return job_list_head;
}

int get_num_jobs ( void )
{
	return num_jobs;
}
