require 'airrecord'
require 'dotenv'
require_relative 'scripts/state_abbr_to_name'

Dotenv.load
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
    hubs = hubs.sort_by { |h| [h['State'], h['Name']] }
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
    return false unless self['City'] && self['State'] && self['Name']
    true
  end

  def state
    STATE_ABBR_TO_NAME[self.fields['State']]
  end

  def map_entry(leaders)
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
      entry[:leaders] = leaders.map { |l| {
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
      leaders = leaders.select do |l|
        l['Role'].to_s =~ /coordinator/i && l['Map?'] == true
      end

      entry = hub.map_entry(leaders)

      json << entry
    end

    json.sort_by { |e| [e[:state], e[:name]] }
  end
end
