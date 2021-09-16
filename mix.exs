defmodule Locksmith.MixProject do
  use Mix.Project

  @scm_url "https://github.com/userpilot/locksmith"

  def project do
    [
      app: :locksmith,
      version: "1.0.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Queue-free/gen_server-free/process-free locking mechanism built for high concurrency.",
      package: package(),

      # ExDoc configurations
      name: "Locksmith",
      source_url: @scm_url,
      homepage_url: @scm_url,
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

  defp package do
    [
      maintainers: ["Ameer A."],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @scm_url,
        "Userpilot" => "https://userpilot.com"
      }
    ]
  end
end
