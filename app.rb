require 'sinatra/base'
require 'pony'
require 'haml'
require 'pry'
require_relative 'airtable'

class EmailLogin < Sinatra::Base
  @@store = {}

  enable :sessions
  set :haml, :format => :html5

  helpers do
    def ensure_current(o)
      o[:email] if o && Time.now - o[:time] <= 10 * 60
    end
  end

  get('/login') { haml :login }

  post('/login')  do
    if @email = params['email']
      key = SecureRandom.urlsafe_base64(32)
      href = url("/login/#{key}")
      time = Time.now
      @@store[key] = { email: @email, time: time }
      logger.info href
      puts href
      Pony.mail(to: @email,
                from: "noreply@sunrisehubhub.com",
                subject: 'Sunrise Hubhub login link!',
                body: "Here's your magic link to log into Sunrise Hubhub: #{href}")
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
    if email = ensure_current(@@store.delete(key))
      session[:user_email] = email
      redirect '/'
    else
      redirect '/login'
    end
  end
end

class Hubhub < Sinatra::Base
  use EmailLogin

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
