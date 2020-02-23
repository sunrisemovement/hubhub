require 'dotenv'

# Locally, load any extra environment variables from a .env file.
# See .env.example for documentation on what variables are required.
Dotenv.load unless ENV['APP_ENV'] == 'test'
