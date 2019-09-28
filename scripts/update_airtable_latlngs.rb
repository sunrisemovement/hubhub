require_relative '../airtable'
require_relative 'state_abbr_to_name'
require 'csv'
require 'pry'
require 'set'

def maybe_add(set, email)
  if email && email.to_s.size > 0
    set << email.strip.downcase
  end
end

`curl https://docs.google.com/spreadsheets/d/1lMgW93xQpWR-louxw7Vm0QY0j5WiNJ_nHMNtn2QsvcQ/export?exportFormat=csv > hubs-from-google.csv`

hub_csv = CSV.parse(File.read('hubs-from-google.csv'), headers: true)

google_hubs = {}

hub_csv.each do |row|
  state = row['State']
  city = row['City/area'].to_s.strip
  lat, lng = row['Lat,Lng'].split(',').map(&:strip).map(&:to_f)

  google_hubs[state] ||= {}
  google_hubs[state][city] ||= {}
  google_hubs[state][city]['state'] ||= state
  google_hubs[state][city]['city'] ||= city
  google_hubs[state][city]['lat'] ||= lat
  google_hubs[state][city]['lng'] ||= lng

  google_hubs[state][city]['fb'] ||= row['Facebook Group Link']
  google_hubs[state][city]['tw'] ||= row['Twitter']
  google_hubs[state][city]['ig'] ||= row['Instagram']
  google_hubs[state][city]['web'] ||= row['Website']
  google_hubs[state][city]['email'] ||= row['Website email'].to_s.strip.downcase
  google_hubs[state][city]['emails'] ||= Set.new()

  maybe_add( google_hubs[state][city]['emails'], row['Website email'] )
  row['Email'].to_s.split('/').each do |email|
    maybe_add( google_hubs[state][city]['emails'], email )
  end

  google_hubs[state][city]['leaders'] ||= []
  google_hubs[state][city]['leaders'] << {
    'first_name': row["Coordinator First Name"],
    'last_name': row["Coordinator Last Name"],
    'email': row['Email'].to_s.strip.downcase
  }
end

inactive_ghubs = []
google_hubs.each do |state, chubs|
  chubs.each do |city, ghub|
    inactive_ghubs << ghub
  end
end

airtable_hubs = Hub.all
airtable_leaders = Leader.all

leaders_by_id = airtable_leaders.each_with_object({}) do |leader, h|
  h[leader.id] = leader
end

social = {
  'facebook': {
    'airtable': 'Facebook Handle',
    'google': 'fb'
  },
  'twitter': {
    'airtable': 'Twitter Handle',
    'google': 'tw'
  },
  'instagram': {
    'airtable': 'Instagram Handle',
    'google': 'ig'
  },
  'website': {
    'airtable': 'Website',
    'google': 'web'
  }
}

active_ghubs = []
matches = 0
airtable_hubs.each do |hub|
  state = [hub['State'], STATE_ABBR_TO_NAME[hub['State']]].detect{|s| google_hubs.key?(s)}
  city = hub['City'].to_s.strip
  name = hub['Name'].to_s.strip
  next unless state
  shubs = google_hubs[state]
  emails = Set.new()
  maybe_add(emails, hub['Email'])
  (hub["Coordinator email"]||[]).each{|em| maybe_add(emails, em)}

  leads = (hub['Hub Leaders'] || []).map{|id| leaders_by_id[id] }
  les = leads.map{|l| l['Email']}
  ghub = nil
  if name.size == 0 and city.size == 0
    puts "blank hub, skipping"
  elsif city.size > 0 && ghub = shubs[city]
    matches += 1
  elsif city.size > 0 && ghub = shubs.detect{|gcity,_| city.downcase == gcity.downcase}
    ghub = ghub[-1]
    matches += 1
  elsif ghub = shubs.detect{|_,v| emails.intersect?(v['emails'])}
    ghub = ghub[-1]
    matches += 1
  elsif ghub = shubs[name.sub(/^Sunrise(?:\sMovement)?\s*/, '')]
    puts name
    matches += 1
  elsif ghub = shubs[name.sub(/\s*Sunrise$/, '')]
    puts name
    matches += 1
  elsif city == 'Bozeman' && ghub = shubs['Gallatin County']
    puts name
    matches += 1
  elsif hub["Activity?"] == "Inactive"
    puts "skipping #{name}, #{city} because it's inactive"
  end

  if ghub
    active_ghubs << ghub
    inactive_ghubs.delete(ghub)
  end
end

puts matches, airtable_hubs.size

CSV.open("inactive_hubs.csv", "wb") do |csv|
  csv << ['City', 'State', 'FB', 'TW', 'IG', 'Emails']
  inactive_ghubs.each do |ghub|
    csv << [ghub['city'], ghub['state'], ghub['fb'], ghub['tw'], ghub['ig'], ghub['emails'].to_a.join("; ")]
  end
end
