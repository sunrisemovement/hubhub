require 'test_helper'

class HubEditingTest < CapybaraTest
  def test_happy_path
    stub_hubs([{
      'Name' => 'Sunrise Rivendell',
      'City' => 'Rivendell',
      'State' => 'PA',
      'Email' => 'sunriserivendell@msn.com',
      'Instagram Handle' => '@elfiestick',
      'Map?' => true
    }])

    log_in_as 'Sunrise Rivendell'
    visit '/map/edit'

    # Page should have hub data populated
    assert_field 'Name', with: 'Sunrise Rivendell'
    assert_field 'Instagram Handle', with: '@elfiestick'

    # Update hub information
    fill_in 'Name', with: 'Sunrise LHH'
    fill_in 'Twitter Handle', with: '@riven-la-vida-loca'
    fill_in 'Latitude', with: '-41.056167'
    fill_in 'Longitude', with: '175.194522'
    click_button 'Update Hub Information'

    # After updating hub info, should see a summary of changes
    within 'tr', text: 'Name' do
      assert_content 'Sunrise Rivendell'
      assert_content 'Sunrise LHH'
    end
    within 'tr', text: 'Twitter Handle' do
      assert_content '@riven-la-vida-loca'
    end
    assert_no_content '@elfiestick'

    json = inline_map_json
    assert json['email'] == "sunriserivendell@msn.com"
    assert json['twitter'] == "https://twitter.com/riven-la-vida-loca"
    assert json['instagram'] == "https://instagram.com/elfiestick"
    assert json['latitude'] == -41.056167
    assert json['longitude'] == 175.194522
  end

  def test_leader_updates
    stub_hubs([{
      'Name' => 'Sunrise Rivendell',
      'City' => 'Rivendell',
      'State' => 'PA',
      'Email' => 'sunriserivendell@msn.com',
      'Contact Type' => 'Hub Email + Leader Emails',
      'Map?' => true,
      'Hub Leaders': ['l1', 'l2']
    }])

    stub_leaders([{
      'id' => 'l1',
      'First Name' => 'Arwen',
      'Last Name' => 'Peredhel',
      'Email' => 'arwen@dell.com',
      'Map?' => true,
    }, {
      'id' => 'l2',
      'First Name' => 'Elrond',
      'Last Name' => 'Peredhel',
      'Email' => 'l.rond@peredh.el',
      'Map?' => true
    }])

    log_in_as 'Sunrise Rivendell'
    visit '/map/edit'
    select 'Leader emails', from: 'contact-type'
    select 'Arwen Peredhel: arwen@dell.com', from: 'Map Leaders[]'
    unselect 'Elrond Peredhel: l.rond@peredh.el', from: 'Map Leaders[]'
    click_button 'Update Hub Information'

    json = inline_map_json
    assert !json['email']
    assert json['leaders'].length == 1
    assert json['leaders'].first['first_name'] == 'Arwen'
  end

  def test_leader_edge_case
    stub_hubs([{
      'Name' => 'Sunrise Rivendell',
      'City' => 'Rivendell',
      'State' => 'PA',
      'Email' => 'sunriserivendell@msn.com',
      'Contact Type' => 'Hub Email + Leader Emails',
      'Map?' => true,
      'Hub Leaders': ['l1', 'l2']
    }])

    stub_leaders([{
      'id' => 'l1',
      'First Name' => 'Arwen',
      'Last Name' => 'Peredhel',
      'Email' => 'arwen@dell.com',
      'Map?' => true,
    }, {
      'id' => 'l2',
      'First Name' => 'Elrond',
      'Last Name' => 'Peredhel',
      'Email' => 'l.rond@peredh.el',
      'Map?' => true
    }])

    log_in_as 'Sunrise Rivendell'
    visit '/map/edit'
    select 'Both hub and leader emails', from: 'contact-type'
    unselect 'Arwen Peredhel: arwen@dell.com', from: 'Map Leaders[]'
    unselect 'Elrond Peredhel: l.rond@peredh.el', from: 'Map Leaders[]'
    click_button 'Update Hub Information'

    json = inline_map_json
    assert json['email'].present?
    assert json['leaders'].blank?
  end
end
