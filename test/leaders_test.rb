require 'test_helper'

class LeadersTest < CapybaraTest
  def test_deleted_leaders_absence
    stub_hubs([{
      'Name' => 'Sunrise Fangorn',
      'City' => 'Fangorn',
      'State' => 'OH',
      'Email' => 'fangorn@netmoot.com',
      'Map?' => true,
      'Hub Leaders': ['l1', 'l2']
    }])

    stub_leaders([{
      'id' => 'l1',
      'First Name' => 'Tree',
      'Last Name' => 'Beard',
      'Deleted by Hubhub?' => false
    }, {
      'id' => 'l2',
      'First Name' => 'Beech',
      'Last Name' => 'Bone',
      'Deleted by Hubhub?' => true
    }])

    log_in_as 'Sunrise Fangorn'
    visit '/leaders'

    assert_content 'Tree Beard'
    assert_no_content 'Beech Bone'
  end

  def test_leader_happy_path
    stub_hubs([{
      'Name' => 'Sunrise Rivendell',
      'City' => 'Rivendell',
      'State' => 'PA',
      'Email' => 'sunriserivendell@msn.com',
      'Map?' => true,
      'Contact Type' => 'Leader Emails',
      'Hub Leaders': ['l1', 'l2']
    }])

    stub_leaders([{
      'id' => 'l1',
      'First Name' => 'Arwen',
      'Last Name' => 'Peredhel',
      'Email' => 'arwen@dell.com',
      'Map?' => true
    }, {
      'id' => 'l2',
      'First Name' => 'Elrond',
      'Last Name' => 'Peredhel',
      'Email' => 'l.rond@peredh.el',
      'Map?' => true
    }])

    log_in_as 'Sunrise Rivendell'
    assert inline_map_json['leaders'].length == 2

    visit '/leaders'

    assert_content 'Arwen'
    assert_content 'arwen@dell.com'
    assert_content 'Elrond'
    assert_content 'l.rond@peredh.el'

    within 'tr', text: 'Elrond' do
      check 'Remove from list'
    end

    click_button 'Update Leader Information'

    assert_content 'Update Summary'
    assert_content 'Elrond'
    assert_no_content 'Arwen'
    assert inline_map_json['leaders'].length == 1
    assert inline_map_json['leaders'].first['first_name'] == 'Arwen'
  end
end
