import Config

config :logger, :default_formatter, metadata: :all

import_config "#{config_env()}.exs"
