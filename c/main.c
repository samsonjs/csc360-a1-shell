/*
 * A simple shell with some basic features.
 *
 * Sami Samhuri 0327342
 * January 31, 2006
 * CSC 360, Assignment 1
 *
 * main.c
 * $Id: main.c 186 2006-01-29 09:06:06Z sjs $
 */

/*#define _GNU_SOURCE*/

/* This must be included before readline or FILE won't be defined. */
#include <stdio.h>

#include <assert.h>
#include <readline/history.h>
#include <readline/readline.h>
#include <signal.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <wordexp.h>

#include "builtins.h"
#include "exec.h"
#include "jobs.h"
#include "utils.h"

#define MAX(a, b) ((a) > (b) ? (a) : (b))

/* looks like this: /path/to/somewhere% */
#define PROMPT BLUE "%s" WHITE "%% " CLEAR

/* for wordexp */
#define INVALID_CHARS "&|;<>"

struct options {
    char *command;
    bool verbose;
};
typedef struct options *options_t;

struct message {
    char *data;
    struct message *next;
};
typedef struct message *message;

static message msg_queue_head = NULL; /* message queue */

/** queue messages so they don't mix with a running program's output
 * instead they're only displayed while waiting on input w/ readline
 * message m: freed in print_messages()
 */
void queue_message(char *msg) {
    message i, m = (message)myxmalloc(sizeof(struct message));
    m->data = strdup(msg);
    m->next = NULL;
    for (i = msg_queue_head; i && i->next; i = i->next)
        ;

    if (!i) /* if i is NULL, then i == msg_queue_head == NULL */
        msg_queue_head = m;
    else /* queue m */
        i->next = m;
}

void free_message_queue(void) {
    message m, n = msg_queue_head;
    while ((m = n)) {
        n = m->next;
        xfree(m->data);
        free(m);
    }
    msg_queue_head = NULL;
}

int print_messages(void) {
    if (!msg_queue_head)
        return 0;

    /* there must be an easier way to interrupt readline... */
    char *old = rl_line_buffer;
    rl_line_buffer = strdup("");
    rl_save_prompt();
    rl_clear_message();

    message m;
    for (m = msg_queue_head; m; m = m->next)
        printf(WHITE "%s\n" CLEAR, m->data);
    free_message_queue();

    xfree(rl_line_buffer);
    rl_line_buffer = old;
    rl_restore_prompt();
    rl_forced_update_display();
    return 1;
}

/* like strerror for waitpid */
char *strsignal(int status) {
    char *str = (char *)myxmalloc(MSGLEN);
    if (WIFEXITED(status)) {
        if (WEXITSTATUS(status)) /* non-zero exit status */
            sprintf(str, RED "exit %i", WEXITSTATUS(status));
        else /* clean exit */
            sprintf(str, GREEN "done");
    }
    if (WIFSIGNALED(status)) {
        switch (WTERMSIG(status)) {
        case SIGTERM:
            sprintf(str, RED "terminated");
            break;

        case SIGKILL:
            sprintf(str, RED "killed");
            break;

        case SIGPIPE:
            sprintf(str, RED "broken pipe");
            break;

        case SIGSEGV:
            sprintf(str, RED "segmentation fault");
            break;

        case SIGABRT:
            sprintf(str, RED "aborted");
            break;

        default:
            sprintf(str, RED "signal %i", WTERMSIG(status));
            break;
        }
    }
    return str;
}

/* handler for SIGCHLD when a child's state changes */
void child_state_changed(int signum) {
    int status;
    pid_t pid;

    /* linux resets the sighandler after each call */
    signal(SIGCHLD, child_state_changed);

    pid = waitpid(-1, &status, WNOHANG);
    job j = job_with_pid(pid);
    if (j) {
        char *strstatus = strsignal(status);
        /* alert the user of the termination, and delete the job */
        size_t len = strlen(j->cmdline);
        char *msg = (char *)myxmalloc(len + MSGLEN);
        snprintf(msg, len + MSGLEN, YELLOW "%i" WHITE ": (pid %i) %s" YELLOW ": %s" CLEAR, j->id, j->pid, strstatus, j->cmdline);
        queue_message(msg);
        xfree(msg);
        xfree(strstatus);
        delete_job(j);
    }
}

/* display the pwd in the prompt */
char *get_prompt(void) {
    char *pwd, *prompt;

    pwd = getcwd(NULL, 0);
    size_t len = strlen(pwd) + strlen(PROMPT);
    prompt = (char *)myxmalloc(len);
    snprintf(prompt, len, PROMPT, pwd);
    xfree(pwd);
    return prompt;
}

int cmd_matches(char *trigger, char *cmd) { return !strcmp(trigger, cmd); }

int handle_wordexp_result(int result, char *cmd) {
    switch (result) {
    case WRDE_BADCHAR:
        /* gcc chokes if the int decl is first, lame */
        ;
        int invalid_char = strcspn(cmd, INVALID_CHARS);
        char *msg = (char *)myxmalloc(strlen(cmd) + MSGLEN);
        int i;
        for (i = 0; i < invalid_char; i++)
            *(msg + i) = ' ';
        sprintf(msg + invalid_char, RED "^ invalid character in column %i", invalid_char + 1);
        queue_message(cmd);
        queue_message(msg);
        xfree(msg);
        result = 0;
        break;
    case WRDE_BADVAL:
        queue_message("undefined variable");
        result = 0;
        break;
    case WRDE_CMDSUB:
        queue_message("no command substitution allowed");
        result = 0;
        break;
    case WRDE_NOSPACE:
        queue_message("not enough memory");
        result = 0;
        break;
    case WRDE_SYNTAX:
        queue_message("syntax error");
        result = 0;
        break;
    default:
        /* success */
        result = 1;
    }
    return result;
}

int process_command(char *line, options_t options) {
    wordexp_t words;
    int result = wordexp(line, &words, WRDE_SHOWERR | WRDE_UNDEF);
    if (handle_wordexp_result(result, line) && words.we_wordc > 0) {
        if (options->verbose) {
            int i;
            fprintf(stderr, "[DEBUG] args = { ");
            for (i = 0; i < words.we_wordc; i++)
                fprintf(stderr, "'%s', ", words.we_wordv[i]);
            fprintf(stderr, "}\n");
        }
        /* try the built-in commands */
        if (cmd_matches("bg", words.we_wordv[0]))
            builtin_bg(words.we_wordc, words.we_wordv);
        else if (cmd_matches("bgkill", words.we_wordv[0]))
            builtin_bgkill(words.we_wordc, words.we_wordv);
        else if (cmd_matches("bglist", words.we_wordv[0]))
            builtin_bglist();
        else if (cmd_matches("cd", words.we_wordv[0]))
            builtin_cd(words.we_wordc, words.we_wordv);
        else if (cmd_matches("clear", words.we_wordv[0]))
            builtin_clear();
        else if (cmd_matches("pwd", words.we_wordv[0]))
            builtin_pwd();
        else if (cmd_matches("exit", words.we_wordv[0])) {
            exit(0);
        } else {
            /* default to trying to execute the command line */
            int retval = exec_command(words.we_wordv, 0);
            if (retval < 0) {
                wordfree(&words);
                return retval;
            }
        }
        add_history(line); /* add to the readline history */
        wordfree(&words);
        return 0;
    } else {
        return -2;
    }
}

void repl_start(options_t options) {
    for (;;) {
        char *prompt = get_prompt();
        char *cmd = readline(prompt);
        xfree(prompt);

        if (!cmd) /* exit if we get an EOF, which returns NULL */
            break;

        process_command(cmd, options);
        free(cmd);
    } /* for (;;) */
}

int main(int argc, char *argv[]) {
    signal(SIGCHLD, child_state_changed); /* catch SIGCHLD */

    /* while waiting for input, display messasges */
    rl_event_hook = print_messages;

    /* register clean-up function */
    atexit(free_job_list);
    atexit(free_message_queue);

    struct options options;

    /* parse command line arguments, skipping over the program name at index 0 */
    for (int i = 1; i < argc; i++) {
        if (strncmp("-c", argv[i], 2) == 0) {
            if (i == argc - 1) {
                printf(RED "[ERROR] " CLEAR "Expected string after -c\n");
                return 1;
            } else {
                i++;
                options.command = argv[i];
            }
        } else if (strncmp("-v", argv[i], 2) == 0 || strncmp("--verbose", argv[i], 9) == 0) {
            options.verbose = true;
        } else {
            printf(RED "[ERROR] " CLEAR "Unknown argument: %s\n", argv[i]);
            return -1;
        }
    }

    if (options.command) {
        int retval = process_command(options.command, &options);
        print_messages();
        return retval;
    }

    repl_start(&options);

    return 0;
}
