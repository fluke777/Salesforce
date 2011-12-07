This is a wrapper for couple of things I usually do with SF
===========================================================

Installation
------------

Prerequisite is having git, ruby and gems installed (also you should have XCode installed since there probably will be need to compile some C code in the background).

    gem install bundler
    git clone git://github.com/fluke777/salesforce.git
    cd salesforce
    bundle install
    rake install


Grabbing fields of a module
---------------------------
Since Force.com explorer cannot search in fields and I love my text editor too much. I created a command how to download the list of fields

    require 'rubygems'
    require 'salesforce'
    
    client = Salesforce::Client.new('login', 'pass+token')
    fields = client.fields('Account')
  
    # if you are looking for a specific one
    fields.grep /Customer/i
  
    # if you did not want a api name you can do whatever you want with describe. For example here I am grabbing label
    response = client.describe('Account')
    response[:describeSObjectResponse][:result][:fields].map {|field| field[:label]}

Downloading data
----------------
You can grab easily some data. Paging is implemented so it will download all the data.

    # grabbing into array (this should probably be the default and it should return the field rather than pasing a reference inside)
    x = []
    client.grab :module => "User", :output => x, :fields => 'Id, Name'
    x.count
    
    # storing it into a file as CSV is easy as well
    require 'fastercsv'
    
    FasterCSV.open('my-csv.csv', 'w') do |csv|
        client.grab :module => "User", :output => csv, :fields => 'Id, Name'
    end
