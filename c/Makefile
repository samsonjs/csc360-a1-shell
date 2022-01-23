CFLAGS = -Wall -g
CPPFLAGS = -I$(shell ./dependency-dir)/readline/include
LDFLAGS = -L$(shell ./dependency-dir)/readline/lib

OBJS = utils.o builtins.o exec.o jobs.o main.o

all: a1

a1: $(OBJS)
	$(CC) $(CFLAGS) -o a1 $(OBJS) $(LDFLAGS) -lreadline -lhistory -ltermcap

test: a1
	cd ../ruby && A1_PATH=../c/a1 bundle exec rake test

clean:
	rm -rf $(OBJS) a1
