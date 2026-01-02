default: c ruby

bootstrap:
	@if command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get update && sudo apt-get install -y libreadline-dev; \
	elif command -v brew >/dev/null 2>&1; then \
		brew list readline >/dev/null 2>&1 || brew install readline; \
	else \
		echo "Please install readline (e.g. libreadline-dev or Homebrew readline)."; \
	fi
	cd ruby && bundle install --jobs 8

c:
	cd c && make test

ruby:
	cd ruby && bundle exec rake

clean:
	cd c && make clean
	cd ruby && bundle exec rake clean

.PHONY: c ruby clean bootstrap
