require 'airrecord'
require_relative 'environment'
require_relative 'scripts/state_abbr_to_name'

Airrecord.api_key = ENV['AIRTABLE_API_KEY']

# Class representing the hub leaders table on Airtable
class Leader < Airrecord::Table
  self.base_key = ENV['AIRTABLE_APP_KEY']
  self.table_name = 'Hub Leaders'

  def name
    "#{self['First Name']} #{self['Last Name']}"
  end

  def entry
    "#{name}: #{self['Email']}"
  end
end

# Class representing the state of the hub forms table on Airtable
class HubForm < Airrecord::Table
  self.base_key = ENV['AIRTABLE_APP_KEY']
  self.table_name = 'State of Hub Forms'
end

# Class representing the hubs table on Airtable
class Hub < Airrecord::Table
  self.base_key = ENV['AIRTABLE_APP_KEY']
  self.table_name = 'Hubs'

  has_many :hub_leaders, class: 'Leader', column: 'Hub Leaders'
  has_many :hub_forms, class: 'HubForm', column: 'State of the Hub Form'

  # Generate a list of hubs that can be edited in Hubhub (for use in the login
  # dropdown list)
  def self.editable_by_coordinators
    hubs = self.all.select(&:editable_by_coordinators?)
    hubs = hubs.sort_by { |h| [h.state_abbrev, h['Name']] }
    if ENV['HUB_BETA_TESTERS']
      hubs = hubs.select { |h| ENV['HUB_BETA_TESTERS'].include?(h.id) }
    end
    hubs
  end

  # A hub is editable in Hubhub if it's been marked as potentially visible on
  # the hub map and if there is at least one login email.
  def editable_by_coordinators?
    return false unless self['Map?'] == true
    return false if login_email.length == 0
    true
  end

  # Valid hub login emails = the hub email plus the emails of any leaders who
  # have been marked as editors (currently only possible to do in Airtable
  # itself)
  def login_email
    emails = []
    ([self['Email']] + (self['Map Editor Emails'] || [])).each do |email|
      unless email.nil?
        emails << email
      end
    end
    emails
  end

  # Ensure that hub.leaders skips leaders that have been soft-deleted on this
  # platform
  def leaders
    hub_leaders.reject { |lead| lead['Deleted by Hubhub?'] }
  end

  # A hub only actually appears on the map (even if it's marked as Map?) if
  # it's active and has the minimum necessary information to render the map
  # card and marker.
  def should_appear_on_map?
    return false if self['Activity'] == 'Inactive'
    return false unless self['Map?'] == true
    return false unless self['Latitude'] && self['Longitude']
    return false unless self['City'] && state && self['Name']
    true
  end

  # The purpose of this is just to get the hub's state abbreviation (e.g. MA or
  # DC). The reason for the complication is that there are two different state
  # fields in Airtable, one which is a linked record, one which is a column. We
  # are transitioning over to the linked record, but there's one complication
  # relating to regions that's preventing this from working completely. An
  # important TODO is to fix this.
  def state_abbrev
    link_abbrev = self['State Link Abbrev']
    link_abbrev = link_abbrev.first if link_abbrev.is_a?(Array)
    orig_abbrev = self['State']
    if link_abbrev && orig_abbrev && link_abbrev != orig_abbrev
      unless ENV['APP_ENV'] == 'production'
        puts "WARNING: #{self['Name']} has a mismatch between #{link_abbrev} and #{orig_abbrev}"
      end

      if STATE_ABBR_TO_NAME.key?(orig_abbrev) && !STATE_ABBR_TO_NAME.key?(link_abbrev)
        return orig_abbrev
      elsif STATE_ABBR_TO_NAME.key?(link_abbrev)
        return link_abbrev
      end
    end
    link_abbrev || orig_abbrev
  end

  # Once we have the state abbreviation, we can get the full state name.
  def state
    STATE_ABBR_TO_NAME[state_abbrev]
  end

  def location
    "#{self['City']}, #{state_abbrev}"
  end

  # Hubs can select a "contact type" that determines which information gets
  # shown on the map.
  def contact_type
    type = self['Contact Type'] || 'Hub Email'
    if type == 'Hub Email' && contact_email.nil?
      'Leader Emails'
    else
      type
    end
  end

  # Depending on the contact type, we can show designated leader names and emails.
  def should_show_leader_emails?
    contact_type.include?('Leader Emails') || contact_type.include?('Coordinator Emails')
  end

  # Depending on the contact type, we can show the hub's contact email
  def should_show_hub_email?
    contact_type.include?('Hub Email')
  end

  # The hub's contact email is either their official email or a custom public
  # email they can provide.
  def contact_email
    self['Custom Map Email'] || self['Email']
  end

  # Combining all of the above functions, we can generate a public map entry
  # that will be used to power the hub map.
  def map_entry(leads=nil)
    entry = {
      name: self.fields['Name'],
      city: self.fields['City'].strip,
      state: self.state,
      latitude: self.fields['Latitude'],
      longitude: self.fields['Longitude'],
      custom_weblink_text: self.fields['Custom Website Link Text'],
      website: self.fields['Website'],
      instagram: self.fields['Instagram Handle'],
      facebook: self.fields['Facebook Handle'],
      twitter: self.fields['Twitter Handle'],
      signup_link: self.fields['Signup Link'],
      leaders: []
    }

    # Handle the hub's contact type
    if contact_type == 'Custom Text'
      # Only show custom text if that's what's given
      entry[:custom_coord_text] = self['Custom Map Contact Text']
    else
      # Otherwise, include the hub email...
      entry[:email] = contact_email if should_show_hub_email?
      # ...and/or leader emails 
      if should_show_leader_emails?
        leads = self.leaders if leads.nil?
        leads = leads.select { |l| l['Map?'] && !l['Deleted by Hubhub?'] }
        entry[:leaders] = leads.map { |l| {
          first_name: l['First Name'],
          last_name: l['Last Name'],
          email: l['Email']
        }}
      end
    end

    entry
  end

  # Return a sorted list of hub map JSON entries. This is what gets uploaded to
  # S3 every 10 minutes and used in the public hub map.
  def self.map_json
    hubs = Hub.all
    leaders = Leader.all

    leaders_by_id = leaders.each_with_object({}) do |leader, h|
      h[leader.id] = leader
    end

    json = []

    hubs.each do |hub|
      next unless hub.should_appear_on_map?
      leaders = (hub.fields['Hub Leaders'] || []).map { |id| leaders_by_id[id] }.compact
      entry = hub.map_entry(leaders)
      json << entry
    end

    json.sort_by { |e| [e[:state], e[:name]] }
  end
end
