require 'pony'

Pony.options = {
  :via => :smtp,
  :via_options => {
    :address              => 'smtp.sendgrid.net',
    :port                 => 587,
    :enable_starttls_auto => true,
    :user_name            => ENV['SENDGRID_USERNAME'],
    :password             => ENV['SENDGRID_PASSWORD'],
    :authentication       => :plain,
    :domain               => "sunrise-hubhub.herokuapp.com"
  }
}

class Emailer
  @last_email = nil

  class << self
    attr_reader :last_email

    def send_email(**kwargs)
      if ENV['APP_ENV'] == 'test'
        @last_email = kwargs
      elsif ENV['APP_ENV'] == 'development'
        puts kwargs
      else
        Pony.mail(from: "Sunrise Hubhub <noreply@sunrise-hubhub.herokuapp.com>", **kwargs)
      end
    end
  end
end
