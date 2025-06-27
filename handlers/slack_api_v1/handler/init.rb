# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), "dependencies"))

class SlackApiV1
  def initialize(input)
    # Set the input document attribute
    @input_document = REXML::Document.new(input)

    # Retrieve all of the handler info values and store them in a hash variable named @info_values.
    @info_values = {}
    REXML::XPath.each(@input_document, "/handler/infos/info") do |item|
      @info_values[item.attributes["name"]] = item.text.to_s.strip
    end

    # Retrieve all of the handler parameters and store them in a hash variable named @parameters.
    @parameters = {}
    REXML::XPath.each(@input_document, "/handler/parameters/parameter") do |item|
      @parameters[item.attributes["name"]] = item.text.to_s.strip
    end

    @enable_debug_logging = @info_values['enable_debug_logging'].downcase == 'yes' ||
                            @info_values['enable_debug_logging'].downcase == 'true'
    puts "Parameters: #{@parameters.inspect}" if @enable_debug_logging

    @api_location = @info_values["api_location"]
    @api_location.chomp!("/")
    @oauth_token = @info_values["oauth_token"]

    @body = @parameters["body"].to_s.empty? ? {} : JSON.parse(@parameters["body"])
    @method = (@parameters["method"] || :get).downcase.to_sym
    @path = @parameters["path"]
    @path = "/#{@path}" if !@path.start_with?("/")

    @accept = :json
    @content_type = :json

  end

  def execute
    error_handling  = @parameters["error_handling"]
    error_message = nil
    response_code = nil

    begin
      response = RestClient::Request.execute(
              method: @method,
              url: "#{@api_location}/#{@path}",
              payload: @body.to_json,
              headers: {
                :authorization => "Bearer #{@oauth_token}",
                :content_type => @content_type,
                :accept => @accept
              }
            )

    rescue RestClient::Exception => e
      error = nil
      response_code = e.response.code

      # Attempt to parse the JSON error message.
      begin
        error = JSON.parse(e.response)
        error_message = error["error"]
        error_key = error["errorKey"] || ""
      rescue Exception
        puts "There was an error parsing the JSON error response" if @debug_logging_enabled
        error_message = e.inspect
      end
      # Raise the error if instructed to, otherwise will fall through to
      # return an error message.
      raise if @error_handling == "Raise Error"
    end

    return <<-RESULTS
    <results>
      <result name="Handler Error Message">#{escape(error_message)}</result>
      <result name="Response Code">#{escape(response_code)}</result>
      <result name="Response Body">#{escape(response.nil? ? {} : response.body)}</result>
    </results>
    RESULTS
  end

  ##############################################################################
  # General handler utility functions
  ##############################################################################

  # This is a template method that is used to escape results values (returned in
  # execute) that would cause the XML to be invalid.  This method is not
  # necessary if values do not contain character that have special meaning in
  # XML (&, ", <, and >), however it is a good practice to use it for all return
  # variable results in case the value could include one of those characters in
  # the future.  This method can be copied and reused between handlers.
  def escape(string)
    # Globally replace characters based on the ESCAPE_CHARACTERS constant
    string.to_s.gsub(/[&"><]/) { |special| ESCAPE_CHARACTERS[special] } if string
  end
  # This is a ruby constant that is used by the escape method
  ESCAPE_CHARACTERS = {'&'=>'&amp;', '>'=>'&gt;', '<'=>'&lt;', '"' => '&quot;'}
end
