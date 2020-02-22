require 'sinatra/base'
require_relative 'emailer'

class Keypad
  @store = {}

  TIMEOUT = 10 * 60

  class << self
    attr_reader :store

    def generate_key(hub)
      old_keys = @store.keys.select{ |k| @store[k][:hub_id] == hub.id }
      old_keys.each do |key|
        @store.delete(key)
      end
      SecureRandom.urlsafe_base64(32).tap do |key|
        @store[key] = { hub_id: hub.id, time: Time.now }
      end
    end

    def enter_key(key)
      @store.each { |k, o| @store.delete(k) if Time.now - o[:time] > TIMEOUT }
      @store.delete(key)
    end
  end
end

class MagicLink < Sinatra::Base
  enable :logging

  set :haml, :format => :html5

  use Rack::Session::Cookie,
    :key => 'rack.session',
    :expire_after => ENV.fetch('SESSION_TIMEOUT', 60*60*24).to_i,
    :secret => ENV.fetch('SESSION_SECRET') { SecureRandom.hex(20) }

  configure do
    if ENV['APP_ENV'] == 'production'
      set :force_ssl, true
    end

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
    @hubs = Hub.editable_by_coordinators
    @states = @hubs.map{ |h| h['State'] }.uniq.sort
    haml :login
  end

  post('/login') do
    if @hub = Hub.find(params['hub'])
      link = url("/login/#{Keypad.generate_key(@hub)}")

      Emailer.send_email(
        to: @hub.login_email,
        subject: "Sunrise Hubhub login link!",
        body: [
          "Hi #{@hub['Name']}!", "",
          "Here's a magic link for signing into the Sunrise Hubhub beta test, where you can control how your hub appears on the Sunrise hub map: #{link}", "",
          "This link will expire in 10 minutes. If you or one of your other hub coordinators did not request it, or if you have any questions, please email us back at this address.", "",
          "Best,",
          "The Hub Support Team"
        ].join("\n")
      )

      haml :email
    else
      redirect '/login'
    end
  end

  get('/logout') do
    session[:hub_id] = nil
    redirect '/login'
  end

  get('/login/:key') do |key|
    if login = Keypad.enter_key(key)
      logger.info "Login successful: Hub #{login[:hub_id]} (#{login[:hub_name]})"
      session[:hub_id] = login[:hub_id]
      redirect '/'
    else
      logger.info "Bad login attempt with key: #{key.inspect}"
      redirect '/login'
    end
  end
end
