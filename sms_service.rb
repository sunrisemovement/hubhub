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

  6371 * c * (miles ? 1 / 1.60934 : 1)
end

class HubChoice
  attr_reader :hub

  def initialize(hub)
    @hub = hub
  end

  def self.parse(sms, data)
    return unless sms.present?

    hubs = Hub.visible

    if hub = hubs.detect { |h| h.name.downcase == sms.downcase }
      new(hub)
    else
      return unless data['hubsearch_hubs'].present?
      return unless sms =~ /^\d\d?$/
      return unless name = data['hubsearch_hubs'][sms.to_i - 1]
      if hub = hubs.detect { |h| h.name == name }
        new(hub)
      end
    end
  end

  def message
    by_signup = signup_message
    on_social = social_message

    if by_signup && on_social
      "You can sign up for #{hub.name} #{by_signup}. "\
      "Also, you can follow #{hub.name} #{on_social} 🙂"
    elsif by_signup
      "You can sign up for #{hub.name} #{by_signup}."
    elsif on_social
      "You can follow #{hub.name} #{on_social}."
    else
      # NOTE: should probably never reach this line, but want to handle it just
      # in case of data issues
      "Unfortunately, #{hub.name} isn't listing any contact or social media "\
      "information right now 😞 Try searching for a different hub!"
    end
  end

  private

  def contact_text
    if hub.contact_type == 'Custom Text'
      hub['Custom Map Contact Text']
    elsif hub.should_show_hub_email?
      hub.contact_email
    elsif hub.should_show_leader_emails?
      emails = hub.leaders.select(&:should_appear_on_map?).map(&:email).compact
      emails.to_sentence(last_word_connector: ', or ')
    end
  end

  def signup_message
    if link = (hub['Signup Link'] || hub['Website']).presence
      "at #{link}"
    elsif whom = contact_text.presence
      "by contacting #{whom}"
    end
  end

  def social_message
    media = {}
    ['twitter', 'facebook', 'instagram'].each do |platform|
      if url = hub.send("#{platform}_url").presence
        media[platform.capitalize] = url.sub(/\?.*$/, '')
      end
    end
    media.map{|platform, url| "#{platform} at #{url}" }.to_sentence.presence
  end
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
  START_HUB_URL = 'http://smvmt.org/start-hub'

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
        Hub.visible.select { |hub| hub.state == state }
      else
        res = []
        Hub.visible.sort_by { |hub| miles_to[hub] }.each do |hub|
          # To start, show all hubs within MIN_MILES miles, unless there are
          # more than MAX_HUBS.  Then, if we haven't yet shown MIN_HUBS hubs,
          # we expand the search radius to MAX_MILES until we have at least
          # MIN_HUBS.
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
    @miles_to ||= Hub.visible.each_with_object({}) do |hub, h|
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

  def hub_message(hub)
    HubChoice.new(hub).message
  end

  def no_hubs_message
    <<-MSG.strip_heredoc.strip
      Sorry, we couldn't find any active Sunrise hubs #{in_location} 😞

      Try searching elsewhere, or consider starting your own: #{START_HUB_URL}
    MSG
  end

  def one_hub_message
    hub = hubs.first

    <<-MSG.strip_heredoc.strip
      Currently, the only hub #{in_location} is #{hub_result(hub)}.

      #{hub_message(hub)}

      If #{hub.name} is far away, you can also consider starting your own hub: #{START_HUB_URL}
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
  HUB_MAP_URL = 'https://sunrisemovement.org/hubs'

  enable :logging

  helpers do
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

      if choice = HubChoice.parse(sms, data)
        res[:message] = choice.message
      elsif search = HubSearch.parse(sms)
        res[:message] = search.message
        res[:member][:custom][:hubsearch_hubs] = search.hubs.map(&:name)
      elsif msg_count == 0
        res[:message] = "Welcome to the Sunrise Movement hub finder chatbot! "\
                        "Try messaging me with a zip code, state name, or hub "\
                        "name to learn more about Sunrise hubs in your region. "\
                        "(You can also find a full list at #{HUB_MAP_URL} 😃)"
      else
        res[:message] = "Sorry, I couldn't figure out what you meant! "\
                        "Try replying back with a zip code, state name, "\
                        "or hub name, and if that doesn't work, "\
                        "you can visit #{HUB_MAP_URL} to see a full list of hubs."
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
