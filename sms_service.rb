require 'sinatra/base'
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
    def zip_coords(sms)
      zip = sms[/\d{5}/]
      zip && ZIP_COORDS[zip]
    end

    def us_state(sms)
      state = STATE_ABBR_TO_NAME.values.detect{|v| sms == v.downcase }
      state ||= STATE_ABBR_TO_NAME[STATE_ABBR_TO_NAME.keys.detect{|v| sms == v.downcase }]
    end

    def active_hubs
      Hub.cached_visible
    end

    def hubs_near(coords, max=99, min=5, radius=10, max_dist=50)
      results = []
      active_hubs.sort_by { |hub| distance(coords, hub.coords) }.each do |hub|
        dist = distance(coords, hub.coords)
        break if results.size >= max
        break if results.size >= min && dist >= radius
        break if dist >= max_dist
        results << hub
      end
      results
    end

    def hubs_in(state)
      active_hubs.select { |hub| hub.state == state }
    end

    def zip_message(hubs, zip, coords)
      if hubs.length == 0
        "Sorry, we couldn't find any active Sunrise hubs within 50 miles of #{zip} 😞\n\nTry searching elsewhere, or consider starting your own: http://smvmt.org/start-hub"
      elsif hubs.length == 1
        hub = hubs.first
        string = "Currently, the only hub within 50 miles of #{zip} is #{hub.name} "
        string += "(~#{distance(coords, hub.coords).round(1)} miles).\n\n"
        string += hub.sms_info
        string += "\n\nIf #{hub.name} is far away, you can also consider starting your own hub: http://smvmt.org/start-hub"
        string
      else
        string = "Here are the hubs we found closest to #{zip}:\n"
        hubs.each_with_index do |hub, i|
          string += "\n#{i+1} - #{hub['Name']} (~#{distance(coords, hub.coords).round(1)} miles) "
        end
        string += "\n\nReply back with 1#{'-'+hubs.size.to_s if hubs.size > 1} or a hub name to learn how to join!"
        string
      end
    end

    def state_message(hubs, state)
      if hubs.length == 0
        "Sorry, we couldn't find any active Sunrise hubs in #{state} 😞\n\nTry searching elsewhere, or consider starting your own hub: http://smvmt.org/start-hub"
      elsif hubs.length == 1
        hub = hubs.first
        string = "Currently, the only hub in #{state} is #{hub.name}.\n\n"
        string += hub.sms_info
        string += "\n\nIf #{hub.name} is far away, you can also consider starting your own hub: http://smvmt.org/start-hub"
        string
      else
        string = "Here are all the #{state} hubs:\n"
        hubs.each_with_index do |hub, i|
          string += "\n#{i+1} - #{hub['Name']} "
        end
        string += "\n\nReply back with 1#{'-'+hubs.size.to_s if hubs.size > 1} or a hub name to learn how to join!"
        string
      end
    end

    def hub_choice(sms, data)
      return unless data['hubsearch_hubs'].present?
      return unless sms =~ /^\d\d?$/
      return unless name = data['hubsearch_hubs'][sms.to_i - 1]
      active_hubs.detect { |h| h.name == name }
    end

    def hub_named(sms)
      active_hubs.detect { |h| h.name.to_s.strip.downcase == sms }
    end

    def sms_response(input)
      sms = input['message'].to_s.strip.downcase
      data = input.fetch('member', {}).fetch('custom', {})
      msg_count = data.fetch('hubsearch_msgs', 0)

      res = {
        continue: true,
        member: {
          custom: {
            hubsearch_msgs: msg_count + 1
          }
        }
      }

      if sms.present? && hub = (hub_choice(sms, data) || hub_named(sms))
        res[:message] = hub.sms_info
      elsif coords = zip_coords(sms)
        hubs = hubs_near(coords)
        res[:message] = zip_message(hubs, sms[/\d{5}/], coords)
        res[:member][:custom][:hubsearch_hubs] = hubs.map(&:name)
      elsif state = us_state(sms)
        hubs = hubs_in(state)
        res[:message] = state_message(hubs, state)
        res[:member][:custom][:hubsearch_hubs] = hubs.map(&:name)
      elsif msg_count == 0
        res[:message] = "Welcome to the Sunrise Movement hub finder chatbot! Try messaging me with a zip code, state name, or hub name to learn more about Sunrise hubs in your region. (You can also find a full list at https://sunrisemovement.org/hubs 😃)"
      else
        res[:message] = "Sorry, I couldn't figure out what you meant! Try replying back with a zip code, state name, or hub name, and if that doesn't work, you can visit https://sunrisemovement.org/hubs to see a full list of hubs."
      end

      res
    end
  end

  get '/sms' do
    sms_response(params).to_json
  end

  post '/sms' do
    input = JSON.parse(request.env['rack.input'].read)
    logger.info input
    sms_response(input).to_json
  end
end
