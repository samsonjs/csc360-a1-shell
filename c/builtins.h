/*
 * A simple shell with some basic features.
 *
 * Sami Samhuri 0327342
 * January 31, 2006
 * CSC 360, Assignment 1
 *
 * builtins.h
 * $Id: builtins.h 184 2006-01-29 08:53:30Z sjs $
 */

int builtin_bg(int argc, char **argv);
int builtin_bgkill(int argc, char **argv);
int builtin_bglist(void);
int builtin_cd(int argc, char **argv);
void builtin_clear(void);
void builtin_pwd(void);
