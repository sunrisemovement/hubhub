require 'test_helper'

class MagicLinkTest < CapybaraTest
  def test_hubmail_happy_path
    stub_hubs([{
      'Name' => 'Sunrise Hobbiton',
      'City' => 'Hobbiton',
      'State' => 'MA',
      'Email' => 'frodo@bagg.ins',
      'Map?' => true
    }])

    visit '/'

    select 'Sunrise Hobbiton', from: 'hub'
    click_button 'Send Magic Link'

    email = Emailer.last_email
    assert_equal email[:to], 'frodo@bagg.ins'
    assert_equal email[:subject], "Sunrise Hubhub login link!"

    magic_link = email[:body][/https?:\/\/[\S]+/]
    visit magic_link

    assert_content 'Edit Hub Information for Hobbiton, MA'
  end

  def test_leader_happy_path
    stub_hubs([{
      'Name' => 'Sunrise Bree',
      'City' => 'Bree',
      'State' => 'NH',
      'Map?' => true,
      'Verified Coordinator Emails' => [
        'butterbur@hotmail.com',
        'nob@fastmail.fm'
      ]
    }])

    visit '/'
    select 'Sunrise Bree', from: 'hub'
    click_button 'Send Magic Link'

    email = Emailer.last_email
    e1, e2 = email[:to]
    assert_equal e1, 'butterbur@hotmail.com'
    assert_equal e2, 'nob@fastmail.fm'
    assert_equal email[:subject], "Sunrise Hubhub login link!"

    magic_link = email[:body][/https?:\/\/[\S]+/]
    visit magic_link

    assert_content 'Edit Hub Information for Bree, NH'
  end

  def test_link_timeout
    stub_hubs([{
      'Name' => 'Sunrise Minas Tirith',
      'City' => 'Minas Tirith',
      'State' => 'GA',
      'Email' => 'f4r4m1r@citadel.org',
      'Map?' => true
    }])

    visit '/'
    select 'Sunrise Minas Tirith', from: 'hub'
    click_button 'Send Magic Link'

    email = Emailer.last_email
    magic_link = email[:body][/https?:\/\/[\S]+/]

    Timecop.freeze(Date.today + 1) do
      visit magic_link
      assert_no_content 'Edit Hub'
    end
  end

  def test_double_link
    stub_hubs([{
      'Name' => 'Sunrise Minas Tirith',
      'City' => 'Minas Tirith',
      'State' => 'GA',
      'Email' => 'f4r4m1r@citadel.org',
      'Map?' => true
    }])

    visit '/'
    select 'Sunrise Minas Tirith', from: 'hub'
    click_button 'Send Magic Link'

    email = Emailer.last_email
    magic_link1 = email[:body][/https?:\/\/[\S]+/]

    visit '/'
    select 'Sunrise Minas Tirith', from: 'hub'
    click_button 'Send Magic Link'

    email = Emailer.last_email
    magic_link2 = email[:body][/https?:\/\/[\S]+/]

    visit magic_link1
    assert_no_content 'Edit Hub'

    visit magic_link2
    assert_content 'Edit Hub Information for Minas Tirith, GA'
  end

  def test_bad_link
    stub_hubs([])
    visit '/login/fgsfgsfgdgdsfdfgsdfg'
    assert_no_content 'Edit Hub'
  end

  def test_only_verified_hubs_with_emails
    stub_hubs([{
      'Name' => 'Sunrise Fangorn',
      'City' => 'Fangorn',
      'State' => 'ME',
      'Email' => 'treebeard@ent.moot',
      'Map?' => true
    }, {
      'Name' => 'Sunrise Isengard',
      'City' => 'Isengard',
      'State' => 'ME',
      'Email' => 'saruman@rw.troll',
      'Map?' => false
    }, {
      'Name' => 'Sunrise Rohan',
      'City' => 'Rohan',
      'State' => 'PA',
      'Email' => nil,
      'Verified Coordinator Emails' => nil,
      'Map?' => true
    }])

    visit '/'
    assert_select 'hub', options: ['Sunrise Fangorn']
    assert_no_select 'hub', with_options: ['Sunrise Isengard']
    assert_no_select 'hub', with_options: ['Sunrise Rohan']
  end
end
