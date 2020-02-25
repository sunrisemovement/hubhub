require 'sinatra/base'
require_relative 'emailer'

# Helper class to store and test temporary secret keys for link-based login.
class Keypad
  @store = {}

  TIMEOUT = 10 * 60 # 10 minute timeout

  class << self
    attr_reader :store

    # Generated keys are specific to hubs and expire after 10 minutes
    def generate_key(hub)
      old_keys = @store.keys.select{ |k| @store[k][:hub_id] == hub.id }
      old_keys.each do |key|
        @store.delete(key)
      end
      # Use `SecureRandom.urlsafe_base64` to generate the key
      SecureRandom.urlsafe_base64(32).tap do |key|
        @store[key] = { hub_id: hub.id, time: Time.now }
      end
    end

    def enter_key(key)
      # First remove any expired keys
      @store.each { |k, o| @store.delete(k) if Time.now - o[:time] > TIMEOUT }
      # Then simultaneously fetch and delete the specific key (returning nil if
      # it does not exist)
      @store.delete(key)
    end
  end
end

class MagicLink < Sinatra::Base
  enable :logging

  set :haml, :format => :html5

  # Ensure cookies expire after 1 day and have a secure session secret key.
  use Rack::Session::Cookie,
    :key => 'rack.session',
    :expire_after => ENV.fetch('SESSION_TIMEOUT', 60*60*24).to_i,
    :secret => ENV.fetch('SESSION_SECRET') { SecureRandom.hex(20) }

  configure do
    if ENV['APP_ENV'] == 'production'
      set :force_ssl, true
    end

    # If running on Heroku, use Memcached for a persistent cookie storage so
    # that people are not logged out when the app dyno restarts.
    if ENV['MEMCACHEDCLOUD_SERVERS']
      require 'dalli'
      require 'rack/session/dalli'
      memcached = Dalli::Client.new(
        ENV["MEMCACHEDCLOUD_SERVERS"].split(','),
        username: ENV["MEMCACHEDCLOUD_USERNAME"],
        password: ENV["MEMCACHEDCLOUD_PASSWORD"]
      )
      use Rack::Session::Dalli, cache: memcached
    end
  end

  get('/login') do
    # When rendering the login page, fetch a list of editable hubs so we can
    # show a dropdown
    @hubs = Hub.editable_by_coordinators
    @states = @hubs.map{ |h| h['State'] }.uniq.sort
    haml :login
  end

  post('/login') do
    # If the user submits a valid hub id
    if @hub = Hub.find(params['hub'])
      logger.info "Attempting login: Hub #{@hub.id} (#{@hub['Name']})"
      # And that hub is indeed editable in Hubhub
      if @hub.editable_by_coordinators?
        # Generate a new 10-minute one-time login key
        link = url("/login/#{Keypad.generate_key(@hub)}")

        # Send them an email with the login key
        Emailer.send_email(
          to: @hub.login_email,
          subject: "Sunrise Hubhub login link!",
          body: [
            "Hi #{@hub['Name']}!", "",
            "Here's a magic link for signing into Sunrise Hubhub, where you can manage information and control how your hub appears on the Sunrise hub map: #{link}", "",
            "This link will expire in 10 minutes. If you or one of your other hub leaders did not request it, you can ignore this email, and if you have any questions, please email us back at #{ENV['GMAIL_USER']}.", "",
            "Best,",
            "The Hub Support Team"
          ].join("\n")
        )

        haml :email
      else
        redirect '/login'
      end
    else
      redirect '/login'
    end
  end

  get('/logout') do
    logger.info "Logging out: Hub #{session[:hub_id]}"
    session[:hub_id] = nil
    redirect '/login'
  end

  get('/login/:key') do |key|
    # Check to ensure the key they submitted is valid
    if session[:hub_id]
      redirect '/'
    elsif login = Keypad.enter_key(key)
      logger.info "Login successful: Hub #{login[:hub_id]}"
      session[:hub_id] = login[:hub_id]
      redirect '/'
    else
      logger.info "Bad login attempt with key: #{key.inspect}"
      @error_msg = "It looks like you tried to log in with a link that was invalid, expired, or already used! Please select your hub from the list and try again."
      @hubs = Hub.editable_by_coordinators
      @states = @hubs.map{ |h| h['State'] }.uniq.sort
      haml :login
    end
  end
end
