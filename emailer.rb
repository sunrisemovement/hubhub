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
