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

  def self.map_json
    hubs = Hub.all
    leaders = Leader.all

    leaders_by_id = leaders.each_with_object({}) do |leader, h|
      h[leader.id] = leader
    end

    json = []
    hubs.each do |hub|
      next if hub.fields['Activity?'] == 'Inactive'
      next unless hub.fields['Map?'] == true
      unless hub.fields['Latitude'] && hub.fields['Longitude']
        puts "Skipping #{hub.fields['Name']} because no lat/lng"
        next
      end

      entry = {
        name: hub.fields['Name'],
        city: hub.fields['City'].strip,
        state: STATE_ABBR_TO_NAME[hub.fields['State']],
        latitude: hub.fields['Latitude'],
        longitude: hub.fields['Longitude'],
        email: hub.fields['Email'],
        custom_coord_text: hub.fields['Custom Map Contact Text'],
        custom_weblink_text: hub.fields['Custom Website Link Text'],
        website: hub.fields['Website'],
        instagram: hub.fields['Instagram Handle'],
        facebook: hub.fields['Facebook Handle'],
        twitter: hub.fields['Twitter Handle'],
        leaders: []
      }

      if hub['Email'].nil? || hub['Always Show Coordinators?'] == true
        leaders = (hub.fields['Hub Leaders'] || []).map { |id| leaders_by_id[id] }
        leaders = leaders.select do |l|
          l['Role'].include?('Coordinator') && l['Map?'] == true
        end
        entry[:leaders] = leaders.map { |l| {
          first_name: l['First Name'],
          last_name: l['Last Name'],
          email: l['Email']
        }}
      end

      json << entry
    end
    json.sort_by { |e| [e[:state], e[:name]] }
  end
end
