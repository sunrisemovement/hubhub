require 'dotenv'
require 'raygun4ruby'

Dotenv.load unless ENV['APP_ENV'] == 'test'

Raygun.setup do |config|
  config.api_key = ENV['RAYGUN_APIKEY']
end
