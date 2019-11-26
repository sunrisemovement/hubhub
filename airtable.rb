require 'airrecord'
require_relative 'environment'
require_relative 'scripts/state_abbr_to_name'

Airrecord.api_key = ENV['AIRTABLE_API_KEY']

class Leader < Airrecord::Table
  self.base_key = ENV['AIRTABLE_APP_KEY']
  self.table_name = 'Hub Leaders'
end

class Hub < Airrecord::Table
  self.base_key = ENV['AIRTABLE_APP_KEY']
  self.table_name = 'Hubs'

  has_many :leaders, class: 'Leader', column: 'Hub Leaders'

  def self.editable_by_coordinators
    hubs = self.all.select(&:editable_by_coordinators?)
    hubs = hubs.sort_by { |h| [h.state_abbrev, h['Name']] }
    if ENV['HUB_BETA_TESTERS']
      hubs = hubs.select { |h| ENV['HUB_BETA_TESTERS'].include?(h.id) }
    end
    hubs
  end

  def login_email
    self['Email'] || self['Verified Coordinator Emails']
  end

  def editable_by_coordinators?
    return false unless self['Map?'] == true
    return false if self['Email'].nil? && (self['Verified Coordinator Emails'] || []).length == 0
    true
  end

  def should_appear_on_map?
    return false if self['Activity?'] == 'Inactive'
    return false unless self['Map?'] == true
    return false unless self['Latitude'] && self['Longitude']
    return false unless self['City'] && state && self['Name']
    true
  end

  def state_abbrev
    link_abbrev = self['State Link Abbrev']
    link_abbrev = link_abbrev.first if link_abbrev.is_a?(Array)
    orig_abbrev = self['State']
    if link_abbrev && orig_abbrev && link_abbrev != orig_abbrev
      puts "WARNING: #{self['Name']} has a mismatch between #{link_abbrev} and #{orig_abbrev}"
    end
    link_abbrev || orig_abbrev
  end

  def state
    STATE_ABBR_TO_NAME[state_abbrev]
  end

  def location
    "#{self['City']}, #{state_abbrev}"
  end

  def map_entry(leads=nil)
    entry = {
      name: self.fields['Name'],
      city: self.fields['City'].strip,
      state: self.state,
      latitude: self.fields['Latitude'],
      longitude: self.fields['Longitude'],
      email: self.fields['Custom Map Email'] || self.fields['Email'],
      custom_coord_text: nil,
      custom_weblink_text: self.fields['Custom Website Link Text'],
      website: self.fields['Website'],
      instagram: self.fields['Instagram Handle'],
      facebook: self.fields['Facebook Handle'],
      twitter: self.fields['Twitter Handle'],
      leaders: []
    }

    if self.fields['Custom Map Contact Text'].to_s.strip.size >= 1
      entry[:email] = nil
      entry[:custom_coord_text] = self.fields['Custom Map Contact Text']
    elsif !entry[:email] || self['Always Show Coordinators?'] == true
      leads = self.leaders if leads.nil?
      leads = leads.select do |l|
        l['Role'].to_s =~ /coordinator/i && l['Map?'] == true
      end
      entry[:leaders] = leads.map { |l| {
        first_name: l['First Name'],
        last_name: l['Last Name'],
        email: l['Email']
      }}
    end

    entry
  end

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
