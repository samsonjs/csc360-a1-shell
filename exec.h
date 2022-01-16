/*
 * A simple shell with some basic features.
 *
 * Sami Samhuri 0327342
 * January 31, 2006
 * CSC 360, Assignment 1
 *
 * exec.h
 * $Id: exec.h 183 2006-01-27 11:24:52Z sjs $
 */
 
/* execute the command argv[0], with arg list argv[], background can be
 * non-zero to run the task in the background under our limited job control */
pid_t exec_command ( char **argv, int background );
