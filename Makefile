CFLAGS = -Wall -g
CPPFLAGS = -I$(shell ./dependency-dir)/readline/include
LDFLAGS = -L$(shell ./dependency-dir)/readline/lib

OBJS = utils.o builtins.o exec.o jobs.o main.o

all: a1

a1: $(OBJS)
	$(CC) $(CFLAGS) -o a1 $(OBJS) $(LDFLAGS) -lreadline -lhistory -ltermcap

clean:
	rm -rf $(OBJS) a1
