CFLAGS = -Wall -g
CPPFLAGS = -I/usr/local/opt/readline/include
LDFLAGS = -L/usr/local/opt/readline/lib

OBJS = utils.o builtins.o exec.o jobs.o main.o

all: a1 

a1: $(OBJS)
	$(CC) $(CFLAGS) -o a1 $(OBJS) $(LDFLAGS) -lreadline -lhistory -ltermcap

clean: 
	rm -rf $(OBJS) a1 
