use Mix.Config

config :logger,
  backends: [{LoggerFileBackend, :dev_backend}],
  level: :info,
  format: "$time $metadata[$level] $message\n"

config :logger, :dev_backend,
  level: :error,
  path: "test/logs/error_$date_$hour.log",
  format: "DEV $message"
