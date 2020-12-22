require 'sinatra/base'
require 'pony'
require 'haml'
require_relative 'airtable'
require_relative 'magic_link'
require_relative 'sms_service'
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
  use SMSService
  use Rack::MethodOverride

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

    def production?
      ENV['APP_ENV'] == 'production'
    end
  end

  # Create a whitelist of hub fields that can be edited via POST /map
  EDITABLE_MAP_FIELDS = [
    'Name', 'Website', 'Latitude', 'Longitude', 'Activity',
    'Facebook Handle', 'Twitter Handle', 'Instagram Handle',
    'Custom Website Link Text', 'Contact Type', 'Signup Link',
    'Custom Map Email', 'Custom Map Contact Text'
  ].freeze

  EDITABLE_MICROSITE_FIELDS = [
    'Name', 'Website', 'Activity',
    'Facebook Handle', 'Twitter Handle', 'Instagram Handle',
    'Custom Website Link Text', 'Signup Link',
    'Donation Link',
    'About Section',
    'Microsite URL Slug',
    'Microsite Display Preference'
  ].freeze

  EDITABLE_LEADER_FIELDS = [
    'First Name', 'Last Name',
    'Pronouns', 'Self Described Pronoun',
    'Email', 'Phone', 'Slack Handle',
    'Primary_Role', 'Secondary_Role',
    'Role - Self Describe', 'Other_Hub_Role(s)',
    'Gender Identity', 'Self Described Gender',
    'Race', 'Self Described Race',
    'Economic/Class Background'
  ].freeze

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

    # Allow for the presentation of one-time flash messages using session
    # variables.
    if session[:notice_msg]
      @notice_msg = session[:notice_msg]
      session[:notice_msg] = nil
    end

    if session[:error_msg]
      @error_msg = session[:error_msg]
      session[:error_msg] = nil
    end
  end

  error do
    haml :error
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

    # Loop through the whitelisted parameters and update the hub accordingly.
    # Keep track of what and whether anything changed.
    @diff = {}
    attrs.each do |attr, value|
      if @hub[attr] != value.presence
        @diff[attr] = [@hub[attr], value]
        @hub[attr] = value.presence
      end
    end

    if production?
      if fparams = params["Update Logo Image"]
        old_image = if @hub['Logo Image'] && @hub['Logo Image'].length > 0
          @hub['Logo Image'][0]['url']
        end
        new_image = upload_file(@hub, fparams, 'logo')
        @hub['Logo Image'] = [{ url: new_image }]
        @diff['Logo Image'] = [old_image, new_image]
      end

      if fparams = params["Update Hero Image"]
        old_image = if @hub['Hero Image'] && @hub['Hero Image'].length > 0
          @hub['Hero Image'][0]['url']
        end
        new_image = upload_file(@hub, fparams, 'hero')
        @hub['Hero Image'] = [{ url: new_image }]
        @diff['Hero Image'] = [old_image, new_image]
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

    @hub.save if @diff.present? && production?

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

    # Loop through the whitelisted parameters and update the hub accordingly.
    # Keep track of what and whether anything changed.
    @diff = {}
    attrs.each do |attr, value|
      if @hub[attr] != value.presence
        @diff[attr] = [@hub[attr], value]
        @hub[attr] = value.presence
      end
    end

    if @diff.key?('Activity') && attrs['Activity'] == 'Inactive'
      logger.info "Setting to inactive: Hub #{@hub.id} (#{@hub['Name']})"
    end

    # If there was an actual change, update the hub on Airtable (assuming we're
    # in production mode). Otherwise, don't do anything so we can prevent an
    # unnecessary Airtable API request.
    @hub.save if @diff.present? && production?

    # Additionally, process changes to leaders, if the hub has been configured
    # to display leader information on the hub map.
    @leaders = nil
    if @hub.should_show_leader_emails?
      # Get the hub's current leaders and cache them by id
      @leaders = @hub.active_leaders
      leads_by_id = {}
      @leaders.each { |lead| leads_by_id[lead.id] = lead }

      # Determine who was previously configured to show up on the hub map vs.
      # who will subsequently show up.
      old = @leaders.select { |lead| lead['Map?'] }
      new_ids = params["Map Leaders"] || []
      old_ids = old.map { |lead| lead.id }
      new = new_ids.map { |id| leads_by_id[id] }

      # Update all of the leaders on Airtable accordingly (need to set their
      # "Map?" checkbox to the right values, though only need to call `.save`
      # if there's a change)
      old.each do |lead|
        unless new_ids.include?(lead.id)
          lead['Map?'] = false
          lead.save if production?
        end
      end

      new.each do |lead|
        unless old_ids.include?(lead.id)
          lead['Map?'] = true
          lead.save if production?
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

  get('/leaders/:id') do
    if @leader = @hub.active_leaders.detect { |l| l.id == params[:id] }
      haml :leader_edit
    else
      session[:error_msg] = "We couldn't find an active #{@hub['Name']} leader with that ID! Perhaps the URL is incorrect, or the leader was removed from the list?"
      redirect '/leaders'
    end
  end

  delete('/leaders/:id') do
    if @leader = @hub.active_leaders.detect { |l| l.id == params[:id] }
      logger.info "Deactivating leader #{params[:id]}: Hub #{@hub.id} (#{@hub['Name']})"
      @leader['Inactive'] = true
      @leader.save if production?
      session[:notice_msg] = "#{@leader.name} has been removed."
      redirect '/leaders'
    else
      session[:error_msg] = "We couldn't find an active #{@hub['Name']} leader with that ID! Perhaps the URL is incorrect, or the leader is already removed from the list?"
      redirect '/leaders'
    end
  end

  post('/leaders/:id') do
    if @leader = @hub.active_leaders.detect { |l| l.id == params[:id] }
      logger.info "Updating leader #{params[:id]}: Hub #{@hub.id} (#{@hub['Name']})"

      attrs = params.slice(*EDITABLE_LEADER_FIELDS)

      @diff = {}
      attrs.each do |attr, value|
        if @leader[attr] != value.presence
          @diff[attr] = [@leader[attr], value]
          @leader[attr] = value.presence
        end
      end

      @leader.save if @diff.present? && production?

      haml :leader_changes
    else
      session[:error_msg] = "We couldn't find an active #{@hub['Name']} leader with that ID! Perhaps the URL is incorrect, or the leader was removed from the list?"
      redirect '/leaders'
    end
  end

  get('/hub_email') do
    haml :hub_email
  end

  post('/hub_email') do
    @email = params['email'].to_s.strip

    raise unless @email.length > 0
    raise unless @email =~ URI::MailTo::EMAIL_REGEXP

    link = url("/hub_email/#{Keypad.generate_key(@hub, @email, 60*60*2)}")

    Emailer.send_email(
      to: @email,
      subject: "Verifying your new Sunrise Hubhub email",
      body: [
        "Hi #{@hub['Name']}!", "",
        "We got a request to update your login email for Sunrise Hubhub from #{@hub['Email']} to #{@email}. To confirm this update, please click on the following link: #{link}", "",
        "This link will expire in 2 hours. If you or one of your other hub leaders did not request it, you can ignore this email, and if you have any questions, please email us back at #{ENV['GMAIL_USER']}.", "",
        "Best,",
        "The Hub Support Team"
      ].join("\n")
    )

    haml :hub_email_sent
  rescue
    @email_error = "We had trouble sending a confirmation email to #{params['email'].to_s.inspect}! This could be because it's an invalid email, or it could be because of an error on our side. If you continue having problems, please email us back at #{ENV['GMAIL_USER']}."

    haml :hub_email_error
  end

  run! if app_file == $0
end
