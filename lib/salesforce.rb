require 'salesforce/version'
require 'rforce'
require 'fastercsv'
require 'active_support/time'
require 'pry'

module Salesforce

  class Client

    attr_accessor :rforce_binding

    def initialize(login, pass, options = {})
      server = options[:server] || "www.salesforce.com"
      url = options[:url] || "https://#{server}/services/Soap/u/26.0"
      @rforce_binding = RForce::Binding.new url
      @rforce_binding.login login, pass
    end

    def describe(mod)
      response = @rforce_binding.describeSObject(:sObject => mod)
      fail(response.to_s) if response.keys.first == :Fault
      response
    end

    def modules
      g = @rforce_binding.describeGlobal
      modules = g[:describeGlobalResponse][:result][:sobjects]
    end

    def fields(mod)
      result = @rforce_binding.describeSObject(:sObject => mod)
      if result.has_key?(:Fault)
        fail result
      end
      fields = result[:describeSObjectResponse][:result][:fields]
      fields.map {|f| f[:name]}
    end

    def grab(options={})
      sf_module = options[:module] || fail("Specify SFDC module")
      fields = options[:fields]
      rforce_binding = @rforce_binding
      output = options[:output]

      if fields == :all
        fields = fields(sf_module)
      elsif fields.kind_of? String
        fields = fields.split(',')
        fields = fields.map {|f| f.strip}
      end

      values = fields.map {|v| v.to_sym}

      query = "SELECT #{values.join(', ')} from #{sf_module}"
      query(query, options.merge(:values => values))
    end

    def query(query, options={})
      values = options[:values]
      as_hash = options[:as_hash]
      counter = 1
      as_hash = true if !as_hash && values.nil?

      rforce_binding = @rforce_binding

      output = options[:output] || []

      begin
        answer = rforce_binding.query({:queryString => query, :batchSize => 2000})
      rescue Timeout::Error => e
        puts "Timeout occured retrying"
        retry
      end

      if answer[:queryResponse].nil? || answer[:queryResponse][:result].nil?
        fail answer[:Fault][:faultstring] if answer[:Fault] && answer[:Fault][:faultstring]
        fail "An unknown error occured while querying salesforce."
      end

      answer[:queryResponse][:result][:records].each {|row| output << (as_hash ? row : row.values_at(*values))} if answer[:queryResponse][:result][:size].to_i > 0

      more_locator = answer[:queryResponse][:result][:queryLocator]

      while more_locator do
        answer_more = rforce_binding.queryMore({:queryLocator => more_locator, :batchSize => 2000})
        answer_more[:queryMoreResponse][:result][:records].each do |row|
          output << (as_hash ? row : row.values_at(*values))
        end
        more_locator = answer_more[:queryMoreResponse][:result][:queryLocator]
      end
      output
    end

    def get_deleted(options={})
      rforce_binding = @rforce_binding
      sf_module = options[:module]
      end_time   = options[:end_time] || Time.now
      start_time = options[:start_time] || end_time.advance(:days => -15)
      fail "The specified start_time cannot be the same value as, or later than, the specified end_time value" unless end_time > start_time
      puts "Downloading from #{start_time} to #{end_time}"
      answer = rforce_binding.getDeleted([:sObjectType, sf_module, :startDate, start_time.utc.iso8601, :endDate, end_time.utc.iso8601])
    end

    def download_deleted(options={})
      output_file = options[:output_file]
      fail "Output file not specified" if output_file.nil?

      answer = get_deleted(options)
      if answer[:getDeletedResponse].nil?
        fail answer[:Fault][:faultstring] if answer[:Fault] && answer[:Fault][:faultstring]
        fail "An unknown error occured during deleted records extraction."
      end

      result = answer[:getDeletedResponse][:result]
      FasterCSV.open(output_file,"w") do |csv|
        csv << ["Timestamp", "Id", "IsDeleted"]
        unless result[:deletedRecords].nil? then
          result[:deletedRecords].each do |record|
            timestamp = Time.parse(record[:deletedDate]).to_i
            csv << [timestamp, record[:id], "true"]
          end
        end
      end

      return result[:earliestDateAvailable], result[:latestDateCovered]
    end

    def download_updated(options={})
      module_name = options[:module]
      end_time   = options[:end_time] || Time.now
      start_time = options[:start_time] || end_time.advance(:days => -1)
      fields_list = options[:fields] || []
      puts "Downloading #{module_name} from #{start_time} to #{end_time}"
      update_answer = rforce_binding.getUpdated([:sObjectType, module_name, :startDate, start_time.utc.iso8601, :endDate, end_time.utc.iso8601])
      results = update_answer[:getUpdatedResponse][:result][:ids]
      if results.nil?
        puts "#{module_name} is empty"
        FasterCSV.open(options[:output_file], 'w') do |csv|
          csv << fields_list
        end
        return update_answer[:getUpdatedResponse][:result][:latestDateCovered]
      end
      puts "Found and downloaded #{results.size} records"
      fields_list = fields_list.map {|x| x.strip.to_sym}

      converters = {
        "datetime"  => lambda {|f| Time.parse(f).utc.to_i rescue f},
        "string"    => lambda {|f| f[0..128] rescue f},
        "textarea"  => lambda {|f| f[0..128] rescue f},
        "date"      => lambda {|f| Time.parse(f).utc.to_i + (12 * 3600) rescue f},
      }

      answer = describe(module_name)
      fields_description = answer[:describeSObjectResponse][:result][:fields]
      my_fields_description = fields_list.map {|f| fields_description.detect {|fl| fl[:name].to_sym == f}}

      my_converters = my_fields_description.map {|fd| converters[fd[:type]]}
      FasterCSV.open(options[:output_file], 'w') do |csv|
        csv << ['Timestamp'] + fields_list
        results.each_slice(2000) do |slice|
          ids = slice.reduce([]) do |memo, item|
            memo.concat [:ID, item]
          end
          result = rforce_binding.retrieve([:fieldList, fields_list.join(', '), :sObjectType, module_name].concat(ids) )
          result[:retrieveResponse][:result].each do |line|

            values = line.values_at(*fields_list).zip(my_converters).map do |value, converter|
             converter.nil? ? value : converter.call(value)
           end
           csv << [Time.parse(update_answer[:getUpdatedResponse][:result][:latestDateCovered]).utc.to_i] + values
          end
        end
      end
      update_answer[:getUpdatedResponse][:result][:latestDateCovered]
    end

  end
end