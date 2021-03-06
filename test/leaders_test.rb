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
      'Inactive' => false
    }, {
      'id' => 'l2',
      'First Name' => 'Beech',
      'Last Name' => 'Bone',
      'Inactive' => true
    }])

    log_in_as 'Sunrise Fangorn'
    visit '/leaders'

    assert_content 'Tree Beard'
    assert_no_content 'Beech Bone'

    visit '/leaders/l2'

    assert_content "We couldn't find an active Sunrise Fangorn leader with that ID!"
    assert_equal current_path, "/leaders"
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

    visit '/leaders'

    assert_content 'Arwen'
    assert_content 'arwen@dell.com'
    assert_content 'Elrond'
    assert_content 'l.rond@peredh.el'

    within 'tr', text: 'Elrond' do
      click_link 'Edit'
    end

    fill_in 'First Name', with: 'Scooby'
    fill_in 'Last Name', with: 'Doo'
    select 'Hub Coordinator', from: 'Primary_Role'

    click_button 'Update Leader Information'

    assert_content 'Update Summary'
    assert_content 'Elrond'
    assert_content 'Scooby'
    assert_no_content 'Arwen'

    visit '/leaders'

    within 'tr', text: 'Arwen' do
      click_button 'Remove'
    end

    assert_content "Arwen Peredhel has been removed."
  end
end
