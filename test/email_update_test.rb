require 'test_helper'

class EmailUpdateTest < CapybaraTest
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
    visit '/hub_email'

    fill_in 'email', with: 'rivvydivvydoo@gmail.com'
    click_button 'Update Hub Email'

    email = Emailer.last_email
    assert_equal email[:to], 'rivvydivvydoo@gmail.com'
    
    magic_link = email[:body][/https?:\/\/[\S]+/]
    visit magic_link

    assert_content 'Hub Email Updated!'
    assert_content 'rivvydivvydoo@gmail.com'
  end

  def test_link_timeout
    stub_hubs([{
      'Name' => 'Sunrise Rivendell',
      'City' => 'Rivendell',
      'State' => 'PA',
      'Email' => 'sunriserivendell@msn.com',
      'Instagram Handle' => '@elfiestick',
      'Map?' => true
    }])

    log_in_as 'Sunrise Rivendell'
    visit '/hub_email'

    fill_in 'email', with: 'rivvydivvydoo@gmail.com'
    click_button 'Update Hub Email'

    email = Emailer.last_email
    magic_link = email[:body][/https?:\/\/[\S]+/]

    Timecop.freeze(Date.today + 1) do
      visit magic_link
      assert_no_content 'Hub Email Updated!'
      assert_no_content 'rivvydivvydoo@gmail.com'
    end
  end

  def test_bad_link
    stub_hubs([{
      'Name' => 'Sunrise Rivendell',
      'City' => 'Rivendell',
      'State' => 'PA',
      'Email' => 'sunriserivendell@msn.com',
      'Instagram Handle' => '@elfiestick',
      'Map?' => true
    }])

    log_in_as 'Sunrise Rivendell'
    visit '/hub_email'

    fill_in 'email', with: 'rivvydivvydoo@gmail.com'
    click_button 'Update Hub Email'

    email = Emailer.last_email
    magic_link = email[:body][/https?:\/\/[\S]+/]

    visit magic_link + "FALSE"

    assert_no_content 'Hub Email Updated!'
    assert_no_content 'rivvydivvydoo@gmail.com'
  end
end
