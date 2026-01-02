csc360-a1-shell
===============

CSC360 assignment 1: `a1.pdf` is the spec. It's a small shell.

The initial C implementation lives in `c/`, and a Ruby implementation and test suite lives in `ruby/`. The Ruby version is just for fun. The Ruby tests can run against any implementation and are used to test the C version as well.

We assume that you have a C compiler.

Bootstrap installs readline and gems:

    make bootstrap

Build and test both the C and Ruby versions:

    make

Build and test just the C version:

    make c

Test the Ruby version:

    make ruby
    # or
    cd ruby && bundle exec rake
