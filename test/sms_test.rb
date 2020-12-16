require 'test_helper'
require 'rack/test'

class SMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Hubhub
  end

  def response_for(data)
    post('/sms', params=data.to_json)
    JSON.parse(last_response.body)
  end

  def test_by_state_vs_zip
    stub_hubs([{
      'Name' => 'Sunrise Rivendell',
      'City' => 'Rivendell',
      'State' => 'PA',
      'Email' => 'sunrisendell@msn.com',
      'Instagram Handle' => '@elfiestick',
      'Latitude' => 40.431478,
      'Longitude' => -80.0505406,
      'Map?' => true
    }, {
      'Name' => 'Sunrise Rohan',
      'City' => 'Rohan',
      'State' => 'PA',
      'Email' => 'sunrise.on.the.fifth.day@helms.deep',
      'Twitter Handle' => '@rohandle',
      'Latitude' => 39.985835,
      'Longitude' => -75.1941506,
      'Map?' => true
    }, {
      'Name' => 'Sunrise Mordor',
      'City' => 'Mordor',
      'State' => 'NJ',
      'Email' => 'mordor.rising@yahoo.com',
      'Latitude' => 40.2161138,
      'Longitude' => -74.809225,
      'Map?' => true
    }])

    # Querying for PA should give us 2/3 hubs
    r = response_for({ message: 'PA' })
    hub_names = r['member']['custom']['hubsearch_hubs']
    message = r['message']
    assert_equal hub_names, ['Sunrise Rivendell', 'Sunrise Rohan']
    assert_includes message, 'Pennsylvania hubs'
    assert_includes message, '1 - Sunrise Rivendell'
    assert_includes message, '2 - Sunrise Rohan'
    refute_includes message, 'Sunrise Mordor'

    # Querying near 19041 (Haverford) should give us a different set of 2/3 hubs
    r = response_for({ message: '19041' })
    hub_names = r['member']['custom']['hubsearch_hubs']
    message = r['message']
    assert_equal hub_names, ['Sunrise Rohan', 'Sunrise Mordor']
    assert_includes message, 'closest to 19041'
    assert_includes message, '1 - Sunrise Rohan (~6.3 miles)'
    assert_includes message, '2 - Sunrise Mordor (~29.9 miles)'
    refute_includes message, 'Sunrise Rivendell'

    # Querying near 15212 (Pittsburg) should just give us one hub
    r = response_for({ message: '15212' })
    message = r['message']
    assert_includes message, 'Sunrise Rivendell'
    assert_includes message, 'elfiestick'
    refute_includes message, 'Sunrise Rohan'
    refute_includes message, 'Sunrise Mordor'

    # Should be able to narrow down our search
    r = response_for({
      message: '1',
      member: { custom: { hubsearch_hubs: ['Sunrise Rohan', 'Sunrise Mordor'] }}
    })
    message = r['message']
    assert_includes message, 'Sunrise Rohan'
    assert_includes message, 'rohandle'
    refute_includes message, 'Sunrise Rivendell'
    refute_includes message, 'Sunrise Mordor'

    # Can also get 0 results
    r = response_for({ message: 'NY' })
    message = r['message']
    assert_includes message, "couldn't find"
    refute_includes message, 'Sunrise Rivendell'
    refute_includes message, 'Sunrise Rohan'
    refute_includes message, 'Sunrise Mordor'
  end
end
