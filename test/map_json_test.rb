require 'test_helper'

def hubby(kwargs)
  h = { 'City' => 'Boston', 'State' => 'MA',
        'Activity?' => 'Active', 'Map?' => true,
        'Latitude' => 42, 'Longitude' => 42 }
  h.merge(kwargs)
end

class MapJSONTest < Minitest::Test
  def test_hub_inclusion
    stub_hubs([
      hubby({'Name' => 'Hub1'}),
      hubby({'Name' => 'Hub2', 'Activity?' => 'Inactive'}),
      hubby({'Name' => 'Hub3', 'Map?' => false}),
      hubby({'Name' => 'Hub4', 'Latitude' => nil}),
      hubby({'Name' => 'Hub5', 'City' => nil}),
      hubby({'Name' => 'Hub6', 'State' => nil})
    ])

    stub_leaders([])

    json = Hub.map_json

    assert_equal json.length, 1

    entry = json.first

    assert_equal entry[:name], 'Hub1'
  end

  def test_leader_inclusion
    stub_hubs([
      hubby({'Name' => 'Hub', 'Hub Leaders': ['l1','l2','l3','l4']})
    ])

    stub_leaders([{
      'id' => 'l1',
      'First Name' => 'A',
      'Last Name' => 'B',
      'Email' => 'a@b.com',
      'Map?' => false,
      'Role' => ['Hub Coordinator']
    }, {
      'id' => 'l2',
      'First Name' => 'C',
      'Last Name' => 'D',
      'Email' => 'c@d.com',
      'Map?' => true,
      'Role' => ['Team Leader']
    }, {
      'id' => 'l3',
      'First Name' => 'E',
      'Last Name' => 'F',
      'Email' => 'e@f.com',
      'Map?' => true,
      'Role' => ['Hub Coordinator']
    }])

    json = Hub.map_json
    assert_equal json.length, 1

    entry = json.first
    leads = entry[:leaders]
    assert_equal leads.length, 1

    lead = leads.first
    assert_equal lead[:first_name], 'E'
    assert_equal lead[:last_name], 'F'
    assert_equal lead[:email], 'e@f.com'
  end

  def test_sort_order
    stub_hubs([
      hubby({'Name' => 'CHub', 'State' => 'PA'}),
      hubby({'Name' => 'BHub', 'State' => 'MA'}),
      hubby({'Name' => 'AHub', 'State' => 'MA'})
    ])

    stub_leaders([])

    json = Hub.map_json
    assert_equal json.length, 3

    names = json.map { |e| e[:name] }
    assert_equal names[0], 'AHub'
    assert_equal names[1], 'BHub'
    assert_equal names[2], 'CHub'

    states = json.map { |e| e[:state] }
    assert_equal states[0], 'Massachusetts'
    assert_equal states[1], 'Massachusetts'
    assert_equal states[2], 'Pennsylvania'
  end

  def test_contact_customization
    stub_hubs([
      hubby({
        'Name': 'Hub1',
        'Email': 'hub1@sunrisemovement.org',
        'Hub Leaders': ['l0']
      }),
      hubby({
        'Name' => 'Hub2',
        'Email': 'hub2@sunrisemovement.org',
        'Custom Map Email': 'hub2-welcome@sunrisemovement.org'
      }),
      hubby({
        'Name': 'Hub3',
        'Email': 'hub3@sunrisemovement.org',
        'Always Show Coordinators?': true,
        'Hub Leaders': ['l1','l2']
      }),
      hubby({
        'Name': 'Hub4',
        'Hub Leaders': ['l3']
      }),
      hubby({
        'Name': 'Hub5',
        'Hub Leaders': ['l4'],
        'Custom Map Contact Text': 'The Hubbet'
      })
    ])

    stub_leaders([{
      'id' => 'l0',
      'First Name' => 'X',
      'Last Name' => 'Z',
      'Email' => 'x@z.com',
      'Map?' => true,
      'Role' => ['Hub Coordinator']
    }, {
      'id' => 'l1',
      'First Name' => 'A',
      'Last Name' => 'B',
      'Email' => 'a@b.com',
      'Map?' => true,
      'Role' => ['Hub Coordinator']
    }, {
      'id' => 'l2',
      'First Name' => 'C',
      'Last Name' => 'D',
      'Email' => 'c@d.com',
      'Map?' => true,
      'Role' => ['Hub Coordinator']
    }, {
      'id' => 'l3',
      'First Name' => 'E',
      'Last Name' => 'F',
      'Email' => 'e@f.com',
      'Map?' => true,
      'Role' => ['Hub Coordinator']
    }, {
      'id' => 'l4',
      'First Name' => 'E',
      'Last Name' => 'F',
      'Email' => 'e@f.com',
      'Map?' => true,
      'Role' => ['Hub Coordinator']
    }])

    hub1, hub2, hub3, hub4, hub5 = Hub.map_json

    assert_equal hub1[:email], 'hub1@sunrisemovement.org'
    assert_equal hub1[:leaders], []

    assert_equal hub2[:email], 'hub2-welcome@sunrisemovement.org'
    assert_equal hub2[:leaders], []

    assert_equal hub3[:email], 'hub3@sunrisemovement.org'
    assert_equal hub3[:leaders].map{|l|l[:email]}, %w(a@b.com c@d.com)

    assert_nil hub4[:email]
    assert_equal hub4[:leaders].map{|l|l[:email]}, %w(e@f.com)

    assert_nil hub5[:email]
    assert_equal hub5[:leaders], []
    assert_equal hub5[:custom_coord_text], 'The Hubbet'
  end
end
