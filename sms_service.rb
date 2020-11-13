require 'sinatra/base'
require 'twilio-ruby'
require_relative 'scripts/state_abbr_to_name'

def distance(geo_a, geo_b, miles=true)
  lat1, lon1 = geo_a
  lat2, lon2 = geo_b

  dLat = (lat2 - lat1) * Math::PI / 180
  dLon = (lon2 - lon1) * Math::PI / 180

  a = Math.sin(dLat / 2) *
      Math.sin(dLat / 2) +
      Math.cos(lat1 * Math::PI / 180) *
      Math.cos(lat2 * Math::PI / 180) *
      Math.sin(dLon / 2) * Math.sin(dLon / 2)

  c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))

  d = 6371 * c * (miles ? 1 / 1.60934 : 1)
end

class SMSService < Sinatra::Base
  ZIP_COORDS = JSON.parse(File.read(File.join(__dir__, 'zip_codes.json')))

  enable :logging

  helpers do
    def active_hubs
      @@active_hubs ||= Hub.all.select(&:should_appear_on_map?)
    end

    def zip_coords(sms)
      zip = sms[/\d{5}/]
      zip && ZIP_COORDS[zip]
    end

    def us_state(sms)
      state = STATE_ABBR_TO_NAME.values.detect{|v| sms == v.downcase }
      state ||= STATE_ABBR_TO_NAME[STATE_ABBR_TO_NAME.keys.detect{|v| sms == v.downcase }]
    end

    def hubs_near(coords, max=99, min=5, radius=10)
      results = []
      active_hubs.sort_by { |hub| distance(coords, hub.coords) }.each do |hub|
        break if results.size >= max
        break if results.size >= min && distance(coords, hub.coords) >= radius
        results << hub
      end
      results
    end

    def hubs_in(state)
      active_hubs.select { |hub| hub.state == state }
    end

    def zip_message(hubs, zip, coords)
      string = "Here are the hubs we found closest to #{zip}:"
      hubs.each_with_index do |hub, i|
        string += "\n #{i+1} - #{hub['Name']} (~#{distance(coords, hub.coords).round(1)} miles) "
      end
      string += "\nReply back with 1#{'-'+hubs.size.to_s if hubs.size > 1} or a hub name to learn how to join!"
      string
    end

    def state_message(hubs, state)
      string = "Here are all the #{state} hubs:"
      hubs.each_with_index do |hub, i|
        string += "\n #{i+1} - #{hub['Name']} "
      end
      string += "\nReply back with 1#{'-'+hubs.size.to_s if hubs.size > 1} or a hub name to learn how to join!"
      string
    end

    def hub_choice(sms)
      return unless session['hub_ids'].present?
      return unless sms =~ /^\d\d?$/
      return unless id = session['hub_ids'][sms.to_i - 1]
      active_hubs.detect { |h| h.id == id }
    end

    def hub_named(sms)
      active_hubs.detect { |h| h['Name'].strip.downcase == sms }
    end

    def sms_response(sms)
      sms = sms.to_s.strip.downcase
      session['msg_count'] ||= 0
      msg_count = session['msg_count']
      session['msg_count'] += 1

      if sms.present? && hub = (hub_choice(sms) || hub_named(sms))
        hub.sms_info
      elsif coords = zip_coords(sms)
        hubs = hubs_near(coords)
        session['hub_ids'] = hubs.map(&:id)
        zip_message(hubs, sms[/\d{5}/], coords)
      elsif state = us_state(sms)
        hubs = hubs_in(state)
        session['hub_ids'] = hubs.map(&:id)
        state_message(hubs, state)
      elsif msg_count == 0
        "Welcome to the Sunrise Movement hub finder chatbot! Try messaging me with a zip code, state name, or hub name to learn more about Sunrise hubs in your region. (You can also find a full list at https://sunrisemovement.org/hubs 😃)"
      else
        "Sorry, I couldn't figure out what you meant! Try replying back with a zip code, state name, or hub name, and if that doesn't work, you can visit https://sunrisemovement.org/hubs to see a full list of hubs."
      end
    end
  end

  get '/sms' do
    sms_response(params['q'])
  end

  post '/sms' do
    twiml = Twilio::TwiML::MessagingResponse.new do |r|
      r.message(body: sms_response(params["Body"]))
    end
    twiml.to_s
  end
end
