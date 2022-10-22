import Config

import Config

config :journey, Journey.Repo,
  database: "journey_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432

config :journey,
  ecto_repos: [Journey.Repo]
