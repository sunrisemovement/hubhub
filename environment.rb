require 'dotenv'

Dotenv.load unless ENV['APP_ENV'] == 'test'
