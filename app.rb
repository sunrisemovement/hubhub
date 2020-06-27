require 'sinatra/base'
require 'pony'
require 'haml'
require_relative 'airtable'
require_relative 'magic_link'
require 'honeybadger' if ENV['HONEYBADGER_API_KEY']
require 'aws-sdk-s3'

def upload_file(hub, attrs, name)
  s3 = Aws::S3::Client.new(
    access_key_id: ENV['AWS_ACCESS_KEY_ID'],
    secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
    region: ENV['AWS_REGION']
  )

  extension = attrs['filename'].split('.').last

  key = "hubs/#{hub.id}/#{name}_#{Time.now.to_i}.#{extension}"

  s3.put_object(
    bucket: ENV['AWS_BUCKET'],
    acl: 'public-read',
    key: key,
    body: attrs['tempfile']
  )

  "https://s3.#{ENV['AWS_REGION']}.amazonaws.com/#{ENV['AWS_BUCKET']}/#{key}"
end

class Hubhub < Sinatra::Base
  use MagicLink

  enable :logging

  helpers do
    def h(text)
      Rack::Utils.escape_html(text)
    end

    def to_sentence(a, join='and')
      arr = a.compact
      case arr.length
      when 0
        ''
      when 1
        arr.first
      when 2
        "#{arr.first} #{join} #{arr.last}"
      else
        "#{arr[0..-2].join(", ")}, #{join} #{arr.last}"
      end
    end

    # Helper function to output JSON loadable by the hub map but specific to
    # the current hub
    def map_entry
      return unless @hub
      leads = instance_variable_defined?(:@leaders) ? @leaders : nil
      { updated_at: Time.now.to_s, map_data: [@hub.map_entry(leads)] }.to_json
    end

    def other_hubs
      return [] unless @hub
      Hub.all.select { |h| h.id != @hub.id }
    end
  end

  # Create a whitelist of hub fields that can be edited via POST /map
  EDITABLE_MAP_FIELDS = [
    'Name', 'Website', 'Latitude', 'Longitude', 'Activity?',
    'Facebook Handle', 'Twitter Handle', 'Instagram Handle',
    'Custom Website Link Text', 'Contact Type', 'Signup Link',
    'Custom Map Email', 'Custom Map Contact Text'
  ]

  EDITABLE_MICROSITE_FIELDS = [
    'Name', 'Website', 'Activity?',
    'Facebook Handle', 'Twitter Handle', 'Instagram Handle',
    'Custom Website Link Text', 'Signup Link',
    'Donation Link',
    'About Section',
    'Microsite URL Slug',
    'Microsite Display Preference'
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

  get '/microsite/edit' do
    @errors = {}
    haml :microsite_edit
  end

  get '/map/json' do
    # Render the current hub's map entry as JSON
    content_type :json
    map_entry
  end

  post '/microsite' do
    logger.info "Editing microsite info: Hub #{@hub.id} (#{@hub['Name']})"

    # Make a container for errors
    @errors = {}
    
    # First, only allow edits to whitelisted fields
    attrs = params.slice(*EDITABLE_MICROSITE_FIELDS)

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

    actually_update = (ENV['APP_ENV'] == 'production')

    if actually_update
      if fparams = params["Update Logo Image"]
        old_image = if @hub['Logo Image'] && @hub['Logo Image'].length > 0
          @hub['Logo Image'][0]['url']
        end
        new_image = upload_file(@hub, fparams, 'logo')
        @hub['Logo Image'] = [{ url: new_image }]
        @diff['Logo Image'] = [old_image, new_image]
        changed = true
      end

      if fparams = params["Update Hero Image"]
        old_image = if @hub['Hero Image'] && @hub['Hero Image'].length > 0
          @hub['Hero Image'][0]['url']
        end
        new_image = upload_file(@hub, fparams, 'hero')
        @hub['Hero Image'] = [{ url: new_image }]
        @diff['Hero Image'] = [old_image, new_image]
        changed = true
      end
    end

    # If the slug is being changed, verify it's valid
    if slug = attrs['Microsite URL Slug'].presence
      if not slug =~ /^[a-z0-9\-]+$/
        @errors['Microsite URL Slug'] = "This value must only contain lower-case letters, numbers, and dashes."
        return haml :microsite_edit
      elsif other_hub = other_hubs.detect { |h| h.url_slug == slug }
        @errors['Microsite URL Slug'] = "Another hub (#{other_hub['Name']} from #{other_hub.location}) is already using /#{other_hub.url_slug}!"
        return haml :microsite_edit
      end
    end

    @hub.save if changed && actually_update

    # Finally, render a summary of the changes so it's clear what happened.
    haml :microsite_changes
  end

  # Make edits to the hub's map information
  post '/map' do
    logger.info "Editing map info: Hub #{@hub.id} (#{@hub['Name']})"

    # First, only allow edits to whitelisted fields
    attrs = params.slice(*EDITABLE_MAP_FIELDS)

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
    logger.info "Editing leader info: Hub #{@hub.id} (#{@hub['Name']})"

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

  get('/hub_email') do
    haml :hub_email
  end

  post('/hub_email') do
    @email = params['email'].to_s.strip

    raise unless @email.length > 0
    raise unless @email =~ URI::MailTo::EMAIL_REGEXP

    link = url("/hub_email/#{Keypad.generate_key(@hub, @email)}")

    Emailer.send_email(
      to: @email,
      subject: "Verifying your new Sunrise Hubhub email",
      body: [
        "Hi #{@hub['Name']}!", "",
        "We got a request to update your login email for Sunrise Hubhub from #{@hub['Email']} to #{@email}. To confirm this update, please click on the following link: #{link}", "",
        "This link will expire in 10 minutes. If you or one of your other hub leaders did not request it, you can ignore this email, and if you have any questions, please email us back at #{ENV['GMAIL_USER']}.", "",
        "Best,",
        "The Hub Support Team"
      ].join("\n")
    )

    haml :hub_email_sent
  rescue
    @email_error = "We had trouble sending a confirmation email to #{params['email'].to_s.inspect}! This could be because it's an invalid email, or it could be because of an error on our side. If you continue having problems, please email us back at #{ENV['GMAIL_USER']}."

    haml :hub_email_error
  end

  get('/hub_email/:key') do |key|
    login = Keypad.enter_key(key)
    if login && login[:hub_id] == @hub.id && login[:metadata]
      new_email = login[:metadata]
      @prev_email = @hub['Email']
      @hub['Email'] = new_email
      @hub.save if ENV['APP_ENV'] == 'production'
      logger.info "Updated hub email: Hub #{@hub.id} (#{@hub['Name']}) switched from #{@prev_email} to #{new_email}"
      haml :hub_email_updated
    else
      logger.info "Bad email update attempt with key: #{key.inspect}"
      @email_error = "It looks like you tried to update your hub's email with a link that was invalid, expired, or already used! Please go back to the edit page and try again (if you want to update your hub's email from #{@hub['Email']} to something else)."
      haml :hub_email_error
    end
  end

  run! if app_file == $0
end
