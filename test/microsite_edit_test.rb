require 'test_helper'

class MicrositeTest < CapybaraTest
  TMP_BASE_URL = "https://foo.bar"

  def setup
    @prev_base_url = ENV['MICROSITE_BASE_URL']
    ENV['MICROSITE_BASE_URL'] = TMP_BASE_URL
    super
  end

  def teardown
    super
    ENV['MICROSITE_BASE_URL'] = @prev_base_url
  end

  def test_happy_path
    stub_hubs([{
      'Name' => 'Sunrise Isengard',
      'City' => 'Orthanc',
      'State' => 'GA',
      'Email' => 'fangorn_fandom@treemail.com',
      'Microsite URL Slug' => 'sunrisengard',
      'Map?' => true
    }])

    log_in_as 'Sunrise Isengard'
    visit '/microsite/edit'

    # Page should have hub data populated
    assert_field 'Name', with: 'Sunrise Isengard'
    assert_field 'Microsite URL Slug', with: 'sunrisengard'
    assert_css "a[href='#{TMP_BASE_URL}/sunrisengard']"

    # Update hub information
    fill_in 'About Section', with: "Sunrise Isengard is committed to supporting GND champions to all the strongholds of Nan Curunír and greater Gondor. Help us elect Treebeard in the upcoming race against Saruman!"
    fill_in 'Microsite URL Slug', with: 'treegarth'
    click_button 'Update Hub Information'

    # After updating hub info, should see a summary of changes
    within 'tr', text: 'About Section' do
      assert_content 'Help us elect Treebeard'
    end
    within 'tr', text: 'Slug' do
      assert_content 'sunrisengard'
      assert_content 'treegarth'
    end
    assert_css "a[href='#{TMP_BASE_URL}/treegarth']"

    # Microsite link should be present
    json = inline_map_json
    assert json['microsite_link'] == 'https://foo.bar/treegarth'
  end

  def test_url_slug_uniqueness
    stub_hubs([{
      'Name' => 'Sunrise Isengard',
      'City' => 'Orthanc',
      'State' => 'GA',
      'Email' => 'fangorn_fandom@treemail.com',
      'Microsite URL Slug' => 'sunrisengard',
      'Map?' => true
    }, {
      'Name' => 'Sunrise Minas Tirith',
      'City' => 'Minas Tirith',
      'State' => 'GA',
      'Email' => 'mean.ass@tir.ith',
      'Microsite URL Slug' => 'minas-tirith',
      'Map?' => true
    }])

    log_in_as 'Sunrise Isengard'
    visit '/microsite/edit'

    fill_in 'Microsite URL Slug', with: 'minas-tirith'
    click_button 'Update Hub Information'

    # assert update fails, but changes are preserved
    assert_content "Another hub (Sunrise Minas Tirith from Minas Tirith, GA) is already using /minas-tirith!"
    assert_field "Microsite URL Slug", with: 'minas-tirith'
  end

  def test_url_slug_format
    stub_hubs([{
      'Name' => 'Sunrise Isengard',
      'City' => 'Orthanc',
      'State' => 'GA',
      'Email' => 'fangorn_fandom@treemail.com',
      'Microsite URL Slug' => 'sunrisengard',
      'Map?' => true
    }, {
      'Name' => 'Sunrise Minas Tirith',
      'City' => 'Minas Tirith',
      'State' => 'GA',
      'Email' => 'mean.ass@tir.ith',
      'Microsite URL Slug' => 'minas-tirith',
      'Map?' => true
    }])

    log_in_as 'Sunrise Isengard'
    visit '/microsite/edit'

    fill_in 'Microsite URL Slug', with: 'Drogo Draggins'
    click_button 'Update Hub Information'

    # assert update fails, but changes are preserved
    assert_content "This value must only contain lower-case letters, numbers, and dashes."
    assert_field "Microsite URL Slug", with: 'Drogo Draggins'
  end

  def test_opting_out
    stub_hubs([{
      'Name' => 'Sunrise Isengard',
      'City' => 'Orthanc',
      'State' => 'GA',
      'Email' => 'fangorn_fandom@treemail.com',
      'Microsite URL Slug' => 'sunrisengard',
      'Map?' => true
    }])

    log_in_as 'Sunrise Isengard'
    visit '/microsite/edit'

    select 'Private (hide from map)', from: 'Microsite Display Preference'
    click_button 'Update Hub Information'

    # Microsite link should be absent
    json = inline_map_json
    assert !json['microsite_link']
  end
end
