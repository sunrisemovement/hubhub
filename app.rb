require 'sinatra/base'
require 'pony'
require 'haml'
require 'honeybadger'
require_relative 'airtable'
require_relative 'magic_link'

class MapPreview < Sinatra::Base
  enable :sessions

  before do
    if session[:hub_id]
      @hub = Hub.find(session[:hub_id])
    end
  end

  get '/map' do
    haml :map
  end
end

class Hubhub < Sinatra::Base
  use MagicLink
  use MapPreview
  enable :logging

  configure :production do
    set :force_ssl, true
  end

  EDITABLE_HUB_FIELDS = [
    'Name', 'Website', 'Latitude', 'Longitude', 'Activity?',
    'Facebook Handle', 'Twitter Handle', 'Instagram Handle',
    'Custom Website Link Text', 'Contact Type',
    'Custom Map Email', 'Custom Map Contact Text'
  ]

  before do
    unless session[:hub_id]
      redirect '/login'
    else
      @hub = Hub.find(session[:hub_id])
    end
  end

  get('/') do
    if @hub
      haml :hub
    else
      haml :notfound
    end
  end

  get('/my_hub_json') do
    content_type :json
    if @hub
      { updated_at: Time.now.to_s, map_data: [@hub.map_entry] }.to_json
    else
      {}.to_json
    end
  end

  post('/leaders') do
    if @hub
      leaders_by_id = @hub.leaders.each_with_object({}) do |leader, h|
        h[leader.id] = leader
      end

      @diffs = {}
      params['leaders'].each do |id, attrs|
        changed = false
        lead = leaders_by_id[id]
        diff = {}
        ['Map?', 'Activity?'].each do |attr|
          old_value = lead[attr]
          new_value = attrs[attr]
          new_value = true if new_value == 'on'
          if old_value != new_value
            diff[attr] = [old_value || false, new_value || false]
            lead[attr] = new_value
            changed = true
          end
        end
        ['First Name', 'Last Name', 'Email'].each do |attr|
          old_value = lead[attr]
          new_value = attrs[attr]
          if old_value != new_value
            diff[attr] = [old_value, new_value]
            lead[attr] = new_value
            changed = true
          end
        end
        if changed
          # TODO: email about this as well?
          lead.save if ENV['APP_ENV'] == 'production'
          @diffs[lead.name] = diff
        end
      end

      if ENV['FEATURE_EMAIL_AFTER_UPDATE']
        Emailer.send_email(
          to: @hub.login_email,
          cc: 'paul@sunrisemovement.org',
          subject: "Sunrise leader info updates for #{@hub.location}",
          body: [
            "Hi #{@hub['Name']},", "",
            "This email is just to confirm that you updated the following information about your hub leaders:", "",
            @diffs.flat_map{|name, d| d.map{|attr,(old,new)| %(- #{name}'s "#{attr}" changed from "#{old}" to "#{new}") } }.join("\n"), "",
            "Some of these changes may update how your card appears on the hub map at https://sunrisemovement.org/hubs. If you did not request these changes, please email us back at this address!", "",
            "Best,",
            "The Hub Support Team"
          ].join("\n")
        )
      end

      haml :leader_changes
    end
  end

  post('/hub') do
    if @hub
      attrs = params.slice(*EDITABLE_HUB_FIELDS)
      ['Latitude','Longitude'].each do |k|
        attrs[k] = attrs[k].to_f if attrs[k] != ""
      end
      attrs.keys.each do |k|
        attrs[k] = nil if attrs[k] == ""
      end
      @diff = {}
      changed = false
      attrs.each do |attr, value|
        if @hub[attr] != value
          @diff[attr] = [@hub[attr], value]
          @hub[attr] = value
          changed = true
        end
      end
      if changed
        @hub.save if ENV['APP_ENV'] == 'production'

        if ENV['FEATURE_EMAIL_AFTER_UPDATE']
          Emailer.send_email(
            to: @hub.login_email,
            cc: 'paul@sunrisemovement.org',
            subject: "Sunrise hub info updates for #{@hub.location}",
            body: [
              "Hi #{@hub['Name']},", "",
              "This email is just to confirm that you updated the following information about your hub:", "",
              @diff.map{|attr,(old,new)| %(- "#{attr}" changed from "#{old}" to "#{new}") }.join("\n"), "",
              "These changes should take effect at https://sunrisemovement.org/hubs within 10 minutes. If you did not request these changes, please email us back at this address!", "",
              "Best,",
              "The Hub Support Team"
            ].join("\n")
          )
        end
      end
      haml :hub_changes
    end
  end

  run! if app_file == $0
end
