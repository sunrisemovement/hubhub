require 'sinatra/base'
require_relative 'scripts/state_abbr_to_name'

# Compute the great circle distance between two sets of [lat,lng] coordinates,
# which approximates the true distance between them. For more details, see
# https://en.wikipedia.org/wiki/Haversine_formula
def haversine_distance(geo_a, geo_b, miles=true)
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

# Wrapper class for parsing hub search parameters, searching for appropriate
# hubs, and printing out a result message
class HubSearch
  ZIP_COORDS = JSON.parse(File.read(File.join(__dir__, 'zip_codes.json')))
  STATE_DICT = STATE_ABBR_TO_NAME
  MIN_HUBS = 5
  MAX_HUBS = 99
  MIN_MILES = 10
  MAX_MILES = 50
  START_HUB = 'http://smvmt.org/start-hub'

  attr_reader :state, :zip

  def initialize(state: nil, zip: nil)
    raise ArgumentError.new("must pass state or zip") unless state || zip
    @state = state
    @zip = zip
  end

  def self.parse(sms)
    if zip = sms[/\d{5}/]
      new(zip: zip) if ZIP_COORDS.key?(zip)
    elsif state = STATE_DICT.values.detect{|v| sms.downcase == v.downcase }
      new(state: state)
    elsif state = STATE_DICT[STATE_DICT.keys.detect{|v| sms.downcase == v.downcase }]
      new(state: state)
    end
  end

  def hubs
    @hubs ||= begin
      if state
        Hub.cached_visible.select { |hub| hub.state == state }
      else
        res = []
        Hub.cached_visible.sort_by { |hub| miles_to[hub] }.each do |hub|
          break if res.size >= MIN_HUBS && miles_to[hub] >= MIN_MILES
          break if res.size >= MAX_HUBS || miles_to[hub] >= MAX_MILES
          res << hub
        end
        res
      end
    end
  end

  def message
    case hubs.length
    when 0
      no_hubs_message
    when 1
      one_hub_message
    else
      many_hubs_message
    end
  end

  private

  def coords
    @coords ||= ZIP_COORDS[zip]
  end

  def miles_to
    @miles_to ||= Hub.cached_visible.each_with_object({}) do |hub, h|
      h[hub] = haversine_distance(coords, hub.coords, miles=true)
    end
  end

  def in_location
    if state
      "in #{state}"
    else
      "within #{MAX_MILES} miles of #{zip}"
    end
  end

  def hub_result(hub)
    if state
      hub.name
    else
      "#{hub.name} (~#{miles_to[hub].round(1)} miles)"
    end
  end

  def no_hubs_message
    <<-MSG.strip_heredoc.strip
      Sorry, we couldn't find any active Sunrise hubs #{in_location} 😞

      Try searching elsewhere, or consider starting your own: #{START_HUB}
    MSG
  end

  def one_hub_message
    <<-MSG.strip_heredoc.strip
      Currently, the only hub #{in_location} is #{hub_result(hubs.first)}.

      #{hubs.first.sms_info}

      If #{hubs.first.name} is far away, you can also consider starting your own hub: #{START_HUB}
    MSG
  end

  def many_hubs_message
    if state
      msg = "Here are all the #{state} hubs:\n"
    else
      msg = "Here are the hubs we found closest to #{zip}:\n"
    end
    hubs.each_with_index do |hub, i|
     msg += "\n#{i+1} - #{hub_result(hub)}"
    end
    msg += "\n\nReply back with 1-#{hubs.size} to learn how to join!"
    msg
  end
end

class SMSService < Sinatra::Base
  enable :logging

  helpers do
    def hub_choice(sms, data)
      return unless data['hubsearch_hubs'].present?
      return unless sms =~ /^\d\d?$/
      return unless name = data['hubsearch_hubs'][sms.to_i - 1]
      Hub.cached_visible.detect { |h| h.name == name }
    end

    def hub_named(sms)
      Hub.cached_visible.detect { |h| h.name.to_s.strip.downcase == sms }
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
      elsif search = HubSearch.parse(sms)
        res[:message] = search.message
        res[:member][:custom][:hubsearch_hubs] = search.hubs.map(&:name)
      elsif msg_count == 0
        res[:message] = "Welcome to the Sunrise Movement hub finder chatbot! Try messaging me with a zip code, state name, or hub name to learn more about Sunrise hubs in your region. (You can also find a full list at https://sunrisemovement.org/hubs 😃)"
      else
        res[:message] = "Sorry, I couldn't figure out what you meant! Try replying back with a zip code, state name, or hub name, and if that doesn't work, you can visit https://sunrisemovement.org/hubs to see a full list of hubs."
      end

      res
    end

    def search_params
      if params && params['message']
        params
      else
        JSON.parse(request.env['rack.input'].read) rescue {}
      end
    end
  end

  get '/sms' do
    sms_response(search_params).to_json
  end

  post '/sms' do
    sms_response(search_params).to_json
  end
end
