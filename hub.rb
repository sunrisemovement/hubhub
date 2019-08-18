require 'airrecord'
require 'dotenv'
require 'pry'

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
end

hubs = Hub.all
leaders = Leader.all

binding.pry
