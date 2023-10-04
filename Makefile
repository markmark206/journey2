.PHONY: \
	build \
	db-init \
	db-reset-test \
	db-local-psql \
	db-local-psql-test \
	dialyzer \
	format \
	install-dependencies \
	lint \
	pre-commit \
	test


build:
	mix compile --force --warnings-as-errors

db-init:
	MIX_ENV=test mix ecto.create
	MIX_ENV=test mix ecto.migrations
	MIX_ENV=test mix ecto.migrate

db-reset-test:
	MIX_ENV=test mix ecto.rollback && MIX_ENV=test mix ecto.migrate

db-local-psql:
	docker exec -it sooshki-postgres psql -U postgres

db-local-psql-test:
	docker exec -it sooshki-postgres psql -U postgres journey_test

dialyzer:
	mix dialyzer

format:
	mix format

install-dependencies:
	mix deps.get

lint:
	MIX_ENV=test mix compile --warnings-as-errors
	MIX_ENV=test mix format --check-formatted
	MIX_ENV=test mix credo --all
	MIX_ENV=test mix hex.audit

livebook-run:
	MIX_ENV=test livebook server

pre-commit: build lint dialyzer test

test:
	mix test --cover --trace  --slowest 4 --warnings-as-errors

test-fast:
	mix test --cover --trace  --slowest 4 --only fast:true --warnings-as-errors

test-show-warnings:
	mix test --max-failures=0 --warnings-as-errors
