defmodule Journey.MixProject do
  use Mix.Project

  def project do
    [
      app: :journey,
      version: "0.1.0",
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: description(),
      dialyzer_cache_directory: "priv/dialzer_cache",
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer_otp24_elixir1.12.1.plt"}
      ],
      name: "Journey",
      source_url: "https://github.com/markmark206/journey2",
      test_coverage: [
        summary: [
          threshold: 87
        ]
      ],
      docs: [
        main: "Journey",
        extras: ["README.md", "LICENSE"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Journey.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp description() do
    "Journey simplifies writing and running persistent workflows."
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.2", only: [:dev], runtime: false},
      {:docception, "~> 0.4", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:ecto_sql, "~> 3.9"},
      {:jason, "~> 1.4"},
      {:nanoid, "~> 2.0.5"},
      {:postgrex, ">= 0.0.0"},
      {:wait_for_it, "~> 1.3.0", only: [:test], runtime: false}
    ]
  end

  def package do
    [
      name: "journey",
      # These are the default files included in the package
      # files: ~w(lib .formatter.exs mix.exs README*  LICENSE*),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/markmark/journey2"}
    ]
  end
end
