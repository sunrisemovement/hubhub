require 'sinatra/base'
require 'pony'
require 'haml'
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
            diff[attr] = [old_value || false, new_value]
            lead[attr] = new_value
            changed = true
          end
        end
        if changed && ENV['APP_ENV'] == 'production'
          #lead.save
        end
        @diffs[lead['Name']] = diff
      end
      haml :leader_changes
    end
  end

  post('/hub') do
    if @hub
      attrs = params.slice(*EDITABLE_HUB_FIELDS)
      attrs['Latitude'] = attrs['Latitude'].to_f
      attrs['Longitude'] = attrs['Longitude'].to_f
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
      if changed && ENV['APP_ENV'] == 'production'
        #@hub.save
      end
      haml :hub_changes
    end
  end

  run! if app_file == $0
end
