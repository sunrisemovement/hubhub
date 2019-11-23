require 'sinatra/base'
require 'pony'
require 'haml'
require_relative 'airtable'
require_relative 'magic_link'

require 'pry'
require 'rb-readline'

class MapPreview < Sinatra::Base
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
    'Facebook Handle', 'Twitter Handle', 'Instagram Handle'
  ]

  EDITABLE_LEADER_FIELDS = [
    'Map?', 'Activity?'
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

  post('/leaders') do
    if @hub
      leaders_by_id = @hub.leaders.each_with_object({}) do |leader, h|
        h[leader.id] = leader
      end

      params['leaders'].each do |id, attrs|
        attrs = attrs.slice(*EDITABLE_LEADER_FIELDS)
        binding.pry
      end
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
      @changes = {}
      attrs.each do |attr, value|
        if @hub[attr] != value
          @changes[attr] = [@hub[attr], value]
          @hub[attr] = value
        end
      end
      logger.info "Hub update: #{@email} #{@changes}"
      if ENV['FEATURE_UPDATE']
        @hub.save
      end
      haml :changes
    end
  end

  run! if app_file == $0
end
