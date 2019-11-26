# Readme for Airtable

## Important Fields

### Fields on `Hubs` Table

* `Name` - Appears as the title for the map cards and sidebar
* `City` - Appears as part of the subtitle in same places
* `State` - Also appears as part of the subtitle. Should be in postal abbreviation on Airtable.
* `Activity?` - Hubs are not included on the map if this field is `Inactive`
* `Map?` - Hubs are not included on the map unless this field is checked
* `Email` - This can show up on the hub map as the hub contact email (more discussion about when below)
* `Custom Map Email` - This can also show up as the hub contact email (more discussion below)
* `Custom Map Contact Text` - Another field that can show up in place of hub/leader emails
* `Contact Type` - Will describe below.
* `Instagram Handle` - Link/handle with or without @. Will appear as a link on card.
* `Facebook Handle` - Link/handle with or without @. Will appear as a link on card.
* `Twitter Handle` - Link/handle with or without @. Will appear as a link on card.
* `Website` - Custom website for the hub.
* `Custom Website Link Text` - Link text for the custom website (defaults to "Hub Website")
* `Latitude`, `Longitude` - Coordinates of the hub on the map.

### Fields on `Hub Leaders` Table

* `First Name`, `Last Name`, `Email` - Basic contact info for coordinators that
  can appear on the map.
* `Map?` - Needs to be checked for the leader to be potentially shown. Must be
  set by a trusted party.

### Logic for how contact info is shown

1. If `Contact Type` is set to `Custom Text`, show `Custom Map Contact Text`
   and don't include any other information in the public data (important for
   hubs that don't want to show emails, e.g. high school hubs like Sunrise
   Georgetown Day School).
2. If `Contact Type` is set to `Hub Email`, show `Email` or `Custom Map Email`
   (which takes precedence over vanilla `Email`) as the "Hub Contact Email"
3. If `Contact Type` is set to `Coordinator Emails`, show the names and email
   addresses of hub leaders who are allowed to be shown on the map.
4. If `Contact Type` is set to `Hub Email + Coordinator Emails`, show both.
5. If `Contact Type` is set to `Hub Email` but no email is actually specified,
   show coordinator emails if there are any.

### Logic for how hubs/leaders are hidden/shown

Hubs aren't included in the map if their `Activity?` level is `Inactive` or if
they are not checked off as `Map?`-ready. The reason for the activity check is
that we want a way to keep storing data about inactive hubs without having to
delete them entirely. The reason for the `Map?` check is that hubs can be
automatically added to list, and we don't want trolls to take advantage of
that. Furthermore, hubs are skipped if any of the main location fields (`Name`,
`City`, `State`, `Latitude`, `Longitude`) are blank.

