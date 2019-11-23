require 'sinatra/base'
require 'pony'

Pony.options = {
  :via => :smtp,
  :via_options => {
    :address              => 'smtp.gmail.com',
    :port                 => '587',
    :enable_starttls_auto => true,
    :user_name            => ENV['GMAIL_USER'],
    :password             => ENV['GMAIL_PASS'],
    :authentication       => :plain,
    :domain               => "localhost.localdomain"
  }
}

class Keypad
  @store = {}

  TIMEOUT = 10 * 60

  class << self
    attr_reader :store

    def generate_key(hub)
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

class Emailer
  @last_email = nil

  class << self
    attr_reader :last_email

    def send_email(to, subject, body)
      if ENV['APP_ENV'] == 'test'
        @last_email = { to: to, subject: subject, body: body }
      elsif ENV['APP_ENV'] == 'development'
        puts to, subject, body
      else
        Pony.mail(to: to, subject: subject, body: body)
      end
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

  post('/login')  do
    if @hub = Hub.find(params['hub'])
      link = url("/login/#{Keypad.generate_key(@hub)}")

      Emailer.send_email(
        @hub.login_email,
        "Sunrise Hubhub login link!",
        "Hi #{@hub['Name']}! Here's your magic link to log into Sunrise Hubhub: #{link}"
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
