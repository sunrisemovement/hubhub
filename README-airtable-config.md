# Getting Airtable Config Info

The Airtable API currently doesn't let you get any information about field configuration (e.g. for rendering dropdowns). However, per [this post](https://community.airtable.com/t/metadata-api-for-schema-and-mutating-tables/1856/6), we can get structured information by visiting <https://airtable.com/apptig05QGFvV5GVd/api/docs> and running the following JS code:

```
var myapp = {
};

for (let table of window.application.tables){
  if (table.name != "Hubs" && table.name != "Hub Leaders") continue;
  myapp[table.name] = {
  };

	for (let column of table.columns){
    let choices = null;
    if (column.typeOptions && column.typeOptions.choices) {
      choices = column.typeOptions.choiceOrder.map(c => column.typeOptions.choices[c].name);
    }
    myapp[table.name][column.name] = {
			type:column.type,
      choices:choices
		};

	}
}

console.log(JSON.stringify(myapp));
```

I then copy the resulting JSON into `airtable_config.json`.
