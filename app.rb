require 'sinatra/base'
require 'pony'
require 'haml'
require_relative 'airtable'
require_relative 'magic_link'
require 'honeybadger' if ENV['HONEYBADGER_API_KEY']

class Hubhub < Sinatra::Base
  use MagicLink

  enable :logging

  helpers do
    def h(text)
      Rack::Utils.escape_html(text)
    end
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
      unless @hub = Hub.find(session[:hub_id])
        redirect '/login'
      end
    end
  end

  get '/' do
    haml :index
  end

  get '/soth' do
    haml :soth_index
  end

  get '/soth/:id' do
    if @soth = @hub.hub_forms.detect { |hf| hf.id == params[:id] }
      haml :soth_show
    else
      haml :soth_index
    end
  end

  get '/map' do
    haml :map_show
  end

  get '/map/edit' do
    haml :map_edit
  end

  get '/map/json' do
    content_type :json
    { updated_at: Time.now.to_s, map_data: [@hub.map_entry] }.to_json
  end

  post '/map' do
    # Only allow edits to specific fields
    attrs = params.slice(*EDITABLE_HUB_FIELDS)

    # Ensure latitude and longitude are coded as floats
    ['Latitude','Longitude'].each do |k|
      attrs[k] = attrs[k].to_f if attrs[k] != ""
    end

    # Ensure blank values get mapped to nil
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
    end

    leads = nil
    if @hub.should_show_leader_emails?
      leads = @hub.leaders
      leads_by_id = {}
      leads.each { |lead| leads_by_id[lead.id] = lead }
      old = leads.select { |lead| lead['Map?'] }
      new_ids = params["Map Leaders"]
      old_ids = old.map { |lead| lead.id }
      new = new_ids.map { |id| leads_by_id[id] }

      old.each do |lead|
        unless new_ids.include?(lead.id)
          lead['Map?'] = false
          lead.save if ENV['APP_ENV'] == 'production'
        end
      end

      new.each do |lead|
        unless old_ids.include?(lead.id)
          lead['Map?'] = true
          lead.save if ENV['APP_ENV'] == 'production'
        end
      end

      @diff['Map Leader Emails'] = [old.map(&:entry), new.map(&:entry)]
    end

    @map_entry_json = {
      updated_at: Time.now.to_s,
      map_data: [@hub.map_entry(leads)]
    }.to_json

    haml :map_changes
  end

  get('/leaders') do
    haml :leaders
  end

  post('/leaders') do
    raise unless @hub

    leaders_by_id = @hub.leaders.each_with_object({}) do |leader, h|
      h[leader.id] = leader
    end

    @removed_leaders = []
    (params['leaders'] || {}).each do |id, attrs|
      next unless lead = leaders_by_id[id]
      next unless attrs['Deleted by Hubhub?'] == 'on'
      lead['Deleted by Hubhub?'] = true
      lead.save if ENV['APP_ENV'] == 'production'
      @removed_leaders << lead
    end

    haml :leader_changes
  end

  run! if app_file == $0
end
