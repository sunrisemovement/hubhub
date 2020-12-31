# Sunrise Hubhub [![Build Status](https://travis-ci.org/sunrisemovement/hubhub.svg?branch=master)](https://travis-ci.org/sunrisemovement/hubhub)

This repository contains code to:
1. integrate Airtable (where hub data mostly lives) with the [Sunrise hub map](https://www.sunrisemovement.org/hubs)
1. allow hubs to manage their data via a web interface
1. support an SMS-based hub search tool

## High-level summary

Using the [Airtable](https://airtable.com/) API, Hubhub (hosted on [Heroku](https://www.heroku.com/)) pulls hub data in [`airtable.rb`](./airtable.rb), converts it to a JSON blob, and pushes it to Amazon S3 in [`scripts/upload_hub_json.rb`](./scripts/upload_hub_json.rb), which is run every 10 minutes by a job scheduler. This JSON blob is then loaded by the hub map in [`public/hub_map.html`](./public/hub_map.html). Hubhub also surfaces this information in an [API](./sms_service.rb) used for a text-messaging flow with [Strive](https://developers.strivedigital.org/).

Finally, Hubhub surfaces a web interface, built with [Sinatra](http://sinatrarb.com/), that lets hubs manage their data (with authentication based on the hub's email).

## Contributing

### Steps to run locally

- clone and `cd` into this repository
- download Ruby 2.6.6
    - if using mac, likely easiest by installing [rbenv](https://github.com/rbenv/rbenv)
    - if additionally using Homebrew, you can run `brew install rbenv && rbenv init && rbenv install 2.6.6 && gem install bundler`
- download and run [memcached](https://memcached.org)
    - if using mac with [Homebrew](https://brew.sh/), can run `brew install memcached` and then `brew services start memcached`
- run `bundle install` to install Ruby dependencies
- ensure `rake test` passes
- set [environment variables](./.env.example) -- note that this may require requesting access to the production or staging Airtable first.
- run `./serve` to view the app
- in development mode, check your logs in the terminal window to find the login link

### Repository structure

- [`airtable.rb`](./airtable.rb) contains the core data modeling. It's mostly a thin wrapper on top of Airtable's API, developed with the excellent [airrecord](https://github.com/Sirupsen/airrecord) library, but it also includes business logic for converting Airtable data into the hub map JSON payload.
- [`app.rb`](./app.rb) and all of the templates in [`views/`](./views/) contain the primary code for the web interface that hubs can use to manage their own data, built using [sinatra](http://sinatrarb.com/).
- [`magic_link.rb`](./magic_link.rb) contains the login logic for hub data management. It handles generating, emailing, and verifying one-time-use login links that get sent to designated hub emails.
- [`sms_service.rb`](./sms_service.rb) contains for a public-facing hub search API, meant to be used with text messages in [Strive](https://developers.strivedigital.org/).
