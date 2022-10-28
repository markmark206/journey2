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

db-reset-test:
	MIX_ENV=test mix ecto.rollback && MIX_ENV=test mix ecto.migrate

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
	mix test --cover --trace  --slowest 4 --warnings-as-errors

test-fast:
	mix test --cover --trace  --slowest 4 --only fast:true --warnings-as-errors

test-show-warnings:
	mix test --max-failures=0 --warnings-as-errors
