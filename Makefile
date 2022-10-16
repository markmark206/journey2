.PHONY: \
	build \
	dialyzer \
	format \
	install-dependencies \
	lint \
	pre-commit \
	test


build:
	mix compile --force

dialyzer:
	 mix dialyzer

format:
	mix format

install-dependencies:
	mix deps.get

lint:
	mix compile
	mix format --check-formatted
	mix credo --all

pre-commit: build lint dialyzer test

test:
	mix test --cover
