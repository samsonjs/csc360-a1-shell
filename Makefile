default: c ruby

bootstrap:
	cd ruby && bundle install --jobs 8

c:
	cd c && make test

ruby:
	cd ruby && bundle exec rake

clean:
	cd c && make clean
	cd ruby && bundle exec rake clean

.PHONY: c ruby clean bootstrap
