require 'test_helper'

class HubEditingTest < CapybaraTest
  def setup
    ENV['FEATURE_EMAIL_AFTER_UPDATE'] = '1'
    super
  end

  def teardown
    ENV.delete('FEATURE_EMAIL_AFTER_UPDATE')
    super
  end

  def test_happy_path
    stub_hubs([{
      'Name' => 'Sunrise Rivendell',
      'City' => 'Rivendell',
      'State' => 'PA',
      'Email' => 'sunriserivendell@msn.com',
      'Instagram Handle' => '@elfiestick',
      'Map?' => true,
      'Activity?' => 'Active',
      'Hub Leaders': ['l1', 'l2']
    }])

    stub_leaders([{
      'id' => 'l1',
      'First Name' => 'Arwen',
      'Last Name' => 'Peredhel',
      'Email' => 'arwen@dell.com',
      'Map?' => true,
      'Activity?' => true
    }, {
      'id' => 'l2',
      'First Name' => 'Elrond',
      'Last Name' => 'Peredhel',
      'Email' => 'l.rond@peredh.el',
      'Map?' => true
    }])

    # Log in
    visit '/'
    select 'Sunrise Rivendell', from: 'hub'
    click_button 'Send Magic Link'
    email = Emailer.last_email
    magic_link = email[:body][/https?:\/\/[\S]+/]
    visit magic_link

    # Page should have hub data populated
    assert_field 'Name', with: 'Sunrise Rivendell'
    assert_field 'Instagram Handle', with: '@elfiestick'

    # Page should have leader data populated
    assert_checked_field 'leaders[l1][Map?]'
    assert_checked_field 'leaders[l2][Map?]'
    assert_checked_field 'leaders[l1][Activity?]'
    assert_no_checked_field 'leaders[l2][Activity?]'
    assert_field 'leaders[l1][First Name]', with: 'Arwen'
    assert_field 'leaders[l1][Email]', with: 'arwen@dell.com'
    assert_field 'leaders[l2][First Name]', with: 'Elrond'
    assert_field 'leaders[l2][Email]', with: 'l.rond@peredh.el'

    # Update hub information
    fill_in 'Name', with: 'Sunrise LHH'
    fill_in 'Twitter Handle', with: '@riven-la-vida-loca'
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

    # An email should also get sent (TODO: maybe.)
    email = Emailer.last_email
    assert_equal email[:subject], "Sunrise hub info updates for Rivendell, PA"
    body = email[:body]
    assert body.include? %{"Name" changed from "Sunrise Rivendell" to "Sunrise LHH"}
    assert body.include? %{"Twitter Handle" changed from "" to "@riven-la-vida-loca"}

    # Now edit leaders
    click_link 'Back to Hub Edit Page'
    check 'leaders[l2][Activity?]'
    uncheck 'leaders[l1][Map?]'
    fill_in 'leaders[l1][Last Name]', with: 'Telcontar'
    click_button 'Update Leader Information'

    # After updating leader info, should see a summary of changes
    within 'tr', text: 'Activity?' do
      assert_content 'Elrond'
      assert_content 'false'
      assert_content 'true'
    end
    within 'tr', text: 'Map?' do
      assert_content 'Arwen'
      assert_content 'true'
      assert_content 'false'
    end
    within 'tr', text: 'Last Name' do
      assert_content 'Arwen'
      assert_content 'Peredhel'
      assert_content 'Telcontar'
    end

    # An email should also get sent (TODO: maybe.)
    email = Emailer.last_email
    assert_equal email[:subject], "Sunrise leader info updates for Rivendell, PA"
    body = email[:body]
    assert body.include? %{Arwen Telcontar's "Last Name" changed from "Peredhel" to "Telcontar"}
    assert body.include? %{Arwen Telcontar's "Map?" changed from "true" to "false"}
    assert body.include? %{Elrond Peredhel's "Activity?" changed from "false" to "true"}
  end
end
