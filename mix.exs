defmodule Locksmith.MixProject do
  use Mix.Project

  def project do
    [
      app: :locksmith,
      version: "1.0.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # ExDoc configurations
      name: "Locksmith",
      source_url: "https://github.com/userpilot/locksmith",
      homepage_url: "https://github.com/userpilot/locksmith",
      docs: [
        main: "README",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      mod: {Locksmith.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:eternal, "~> 1.2"},

      # Development dependencies
      {:credo, "~> 1.5", only: :dev, runtime: false},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false}
    ]
  end
end
