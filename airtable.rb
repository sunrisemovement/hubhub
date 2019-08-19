require 'airrecord'
require 'dotenv'

Dotenv.load
Airrecord.api_key = ENV['AIRTABLE_API_KEY']

class Leader < Airrecord::Table
  self.base_key = ENV['AIRTABLE_APP_KEY']
  self.table_name = "Hub Leaders"
end

class Hub < Airrecord::Table
  self.base_key = ENV['AIRTABLE_APP_KEY']
  self.table_name = "Hubs"

  has_many :leaders, class: 'Leader', column: 'Hub Leaders'

  def self.map_json
    hubs = Hub.all
    leaders = Leader.all

    leaders_by_id = leaders.each_with_object({}) do |leader, h|
      h[leader.id] = leader
    end

    hubs.map { |hub|
      {
        name: hub.fields['Name'],
        city: hub.fields['City'],
        state: hub.fields['State'],
        email: hub.fields['Email'],
        website: hub.fields['Website'],
        instagram: hub.fields['Instagram Handle'],
        facebook: hub.fields['Facebook Handle'],
        twitter: hub.fields['Twitter Handle'],
        leaders: (hub.fields['Hub Leaders'] || []).map { |id| leaders_by_id[id] }.map { |lead|
          {
            first_name: lead.fields['First Name'],
            last_name: lead.fields['Last Name'],
            pronouns: lead.fields['Pronouns'],
            email: lead.fields['Email']
          }
        }
      }
    }
  end
end
