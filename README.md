# Sunrise Hub Map + Airtable

This repository contains code to help integrate Airtable (the eventual canonical source of hub data) with the [Sunrise hub map](https://www.sunrisemovement.org/hubs) and potentially other public or coordinator-facing applications.

## Some background

Currently, the hub map is powered by Google Sheets (see [the map's github repo](https://github.com/sunrisemovement/sunrise-movement-hub-map) for more details). However, keeping data synced currently requires a decent amount of error-prone manual work, and comes with downsides like the inability to make atomic edits of multiple fields. There are also issues keeping track of which hubs are active and exactly what information should be public and private.

## This repo

### New Hub Map

Using the [Airtable API](https://airtable.com/apptig05QGFvV5GVd/api/docs) (ask about access on Slack) and the excellent [airrecord](https://github.com/sirupsen/airrecord) Ruby library, we pull hub and coordinator data in [`airtable.rb`](./airtable.rb), convert it to a JSON blob, and push it to Amazon S3 in [`scripts/upload_hub_json.rb`](./scripts/upload_hub_json.rb). We use this to power a (rough) new version of the hub map in [`public/hub_map.html`](./public/hub_map.html).

The Airtable data still needs some cleaning (especially around names and links), and as part of this process, we'll want flags on each hub and each coordinator indicating whether they are active and whether they should be shown on the map.

### Coordinator Data Management

This repo also contains a small [sinatra](http://sinatrarb.com/)-based web application that uses the Airtable API to generate an edit form for hub information related to the map (i.e. latitude and longitude, social media links, etc).

Authentication is currently inspired by Slack's "magic link" method, where you click on a link that gets sent to your email address instead of entering a password. This is convenient because it means we don't have to manage user accounts, and because we can simultaneously implement authorization -- that is, you would have authority to edit hubs if you have access to the hub email address (or are listed as a coordinator on Airtable). This is currently implemented (but just for the hub email); however, we definitely might want extra layers of security.

### Diagram (updated Sep. 29, 2019)

![diagram](./infra-diagram.png)

## Where this is going

This is still definitely a work in progress, and when/whether we roll it out will be a group decision. However, feel free to message `@asross` if this is exciting to you or if you want to help out!
