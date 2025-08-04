defmodule Axn.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/guess/axn"

  def project do
    [
      app: :axn,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "Axn",
      source_url: @source_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: [:dev], runtime: false},
      {:params, "~> 2.0"},
      {:styler, "~> 1.1", only: [:dev, :test]}
    ]
  end

  defp description do
    """
    A clean, step-based DSL library for defining actions with parameter validation,
    authorization, telemetry, and custom business logic. Prioritizes simplicity,
    explicitness, and ease of following execution flow.
    """
  end

  defp package do
    [
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/axn"
      },
      maintainers: ["Steve Domin"]
    ]
  end

  defp docs do
    [
      main: "Axn",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Guides: ~r/docs\/.*/
      ]
    ]
  end
end
