require 'sinatra/base'
require 'pony'
require 'haml'
require 'pry'
require_relative 'airtable'

TIMEOUT = 10 * 60

class MagicLink < Sinatra::Base
  @@store = {}

  enable :sessions
  set :haml, :format => :html5

  helpers do
    def ensure_current_key(o)
      o[:email] if o && Time.now - o[:time] <= TIMEOUT
    end

    def ensure_valid_email(s)
      s if s && s =~ URI::MailTo::EMAIL_REGEXP
    end
  end

  get('/login') do
    @@store.each { |k, o| @@store.delete(k) if Time.now - o[:time] > TIMEOUT }

    haml :login
  end

  post('/login')  do
    if @email = ensure_valid_email(params['email'])
      key = SecureRandom.urlsafe_base64(32)
      href = url("/login/#{key}")
      time = Time.now
      @@store[key] = { email: @email, time: time }
      if ENV['DEBUG'] == 'DEBUG'
        puts "DEBUG: #{href}"
      else
        Pony.mail(to: @email,
                  from: 'noreply@sunrisemovement.org',
                  subject: 'Sunrise Hubhub login link!',
                  body: "Here's your magic link to log into Sunrise Hubhub: #{href}")
      end
      haml :email
    else
      redirect '/login'
    end
  end

  get('/logout') do
    session[:user_email] = nil
    redirect '/login'
  end

  get('/login/:key') do |key|
    if email = ensure_current_key(@@store.delete(key))
      session[:user_email] = email
      redirect '/'
    else
      redirect '/login'
    end
  end
end

class Hubhub < Sinatra::Base
  use MagicLink

  before do
    unless session[:user_email]
      redirect '/login'
    end
  end

  get('/') do
    if @hub = Hub.all(filter: %|{Email} = "#{session[:user_email]}"|).first
      @leaders = @hub.leaders
      haml :hub
    else
      "Couldn't find a hub matching #{session[:user_email]}"
    end
  end

  run! if app_file == $0
end
