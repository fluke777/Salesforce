This is a wrapper for couple of things I usually do with SF

* Grabbing fields of a module
Since Force.com explorer cannot search in fields and I love my text editor too much. I created a command how to download the list of fields

  client = Salesforce::Client.new('login', 'pass+token')
  fields = client.fields('Account')
  
  # if you are looking for a specific one
  fields.grep /Customer/i
  
  # if you did not want a api name you can do whatever you want with describe. For example here I am grabbing label
  response = client.describe('Account')
  response[:describeSObjectResponse][:result][:fields].map {|field| field[:label]}

* Downloading data

It is implemented I just need to think about more suitable API
