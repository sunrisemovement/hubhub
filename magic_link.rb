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
  enable :sessions
  set :haml, :format => :html5

  get('/login') do
    @hubs = Hub.editable_by_coordinators
    @states = @hubs.map{ |h| h['State'] }.uniq.sort
    haml :login
  end

  post('/login') do
    if @hub = Hub.find(params['hub'])
      link = url("/login/#{Keypad.generate_key(@hub)}")

      email_lines = [
        "Hi #{@hub['Name']}!",
        "",
        "Here's a magic link for signing into the Sunrise Hubhub beta test, where you can control how your hub appears on the Sunrise hub map: #{link}",
        "",
        "This link will expire in 10 minutes. If you or one of your other hub coordinators did not request it, or if you have any questions, please email paul@sunrisemovement.org or message us in #hubtalk.",
        "",
        "Best,",
        "The Hub Support Team"
      ]

      Emailer.send_email(
        @hub.login_email,
        "Sunrise Hubhub login link!",
        email_lines.join("\n")
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
