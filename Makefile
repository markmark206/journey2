.PHONY: \
	build \
	dialyzer \
	format \
	install-dependencies \
	lint \
	pre-commit \
	test


build:
	time mix compile --force

dialyzer:
	 time mix dialyzer

format:
	mix format

install-dependencies:
	mix deps.get

lint:
	time mix compile
	mix format --check-formatted
	mix credo --all

pre-commit: build lint dialyzer test

test:
	time mix test --cover
