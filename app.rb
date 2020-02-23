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

    # Helper function to output JSON loadable by the hub map but specific to
    # the current hub
    def map_entry
      return unless @hub
      leads = instance_variable_defined?(:@leaders) ? @leaders : nil
      { updated_at: Time.now.to_s, map_data: [@hub.map_entry(leads)] }.to_json
    end
  end

  # Create a whitelist of hub fields that can be edited via POST /map
  EDITABLE_HUB_FIELDS = [
    'Name', 'Website', 'Latitude', 'Longitude', 'Activity?',
    'Facebook Handle', 'Twitter Handle', 'Instagram Handle',
    'Custom Website Link Text', 'Contact Type', 'Signup Link',
    'Custom Map Email', 'Custom Map Contact Text'
  ]

  before do
    # To access any of these pages, ensure the user is logged in with a valid
    # hub.
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
    # Ensure that the form being accessed exists and belongs to the current hub
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
    # Render the current hub's map entry as JSON
    content_type :json
    map_entry
  end

  # Make edits to the hub's map information
  post '/map' do
    # First, only allow edits to whitelisted fields
    attrs = params.slice(*EDITABLE_HUB_FIELDS)

    # Ensure latitude and longitude are coded as floats
    ['Latitude','Longitude'].each do |k|
      attrs[k] = attrs[k].to_f if attrs[k] != ""
    end

    # Ensure blank values get mapped to nil
    attrs.keys.each do |k|
      attrs[k] = nil if attrs[k] == ""
    end

    # Loop through the whitelisted parameters and update the hub accordingly.
    # Keep track of what and whether anything changed.
    @diff = {}
    changed = false
    attrs.each do |attr, value|
      if @hub[attr] != value
        @diff[attr] = [@hub[attr], value]
        @hub[attr] = value
        changed = true
      end
    end

    # If there was an actual change, update the hub on Airtable (assuming we're
    # in production mode). Otherwise, don't do anything so we can prevent an
    # unnecessary Airtable API request.
    if changed
      @hub.save if ENV['APP_ENV'] == 'production'
    end

    # Additionally, process changes to leaders, if the hub has been configured
    # to display leader information on the hub map.
    @leaders = nil
    if @hub.should_show_leader_emails?
      # Get the hub's current leaders and cache them by id
      @leaders = @hub.leaders
      leads_by_id = {}
      @leaders.each { |lead| leads_by_id[lead.id] = lead }

      # Determine who was previously configured to show up on the hub map vs.
      # who will subsequently show up.
      old = @leaders.select { |lead| lead['Map?'] }
      new_ids = params["Map Leaders"]
      old_ids = old.map { |lead| lead.id }
      new = new_ids.map { |id| leads_by_id[id] }

      # Update all of the leaders on Airtable accordingly (need to set their
      # "Map?" checkbox to the right values, though only need to call `.save`
      # if there's a change)
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

      # Record the leader changes in the diff.
      @diff['Map Leader Emails'] = [old.map(&:entry), new.map(&:entry)]
    end

    # Finally, render a summary of the changes so it's clear what happened.
    haml :map_changes
  end

  get('/leaders') do
    haml :leaders
  end

  post('/leaders') do
    # Fetch the hub's leaders
    @leaders = @hub.leaders
    leaders_by_id = @leaders.each_with_object({}) do |leader, h|
      h[leader.id] = leader
    end

    # Loop through all of the leaders and determine if any have the removal
    # checkbox checked
    @removed_leaders = []
    (params['leaders'] || {}).each do |id, attrs|
      next unless lead = leaders_by_id[id]
      next unless attrs['Deleted by Hubhub?'] == 'on'
      # If they do have the removal checkbox checked, mark them for soft
      # deletion on Airtable
      lead['Deleted by Hubhub?'] = true
      lead.save if ENV['APP_ENV'] == 'production'
      @removed_leaders << lead
    end

    # Render a summary of the leaders removed
    haml :leader_changes
  end

  run! if app_file == $0
end
