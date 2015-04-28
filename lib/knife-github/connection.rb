require 'json'
require 'uri'
require 'cgi'
require 'openssl'
require 'net/http'

module GithubClient
 class Connection

    def request(params)
      ssl_verify_mode = Chef::Config[:knife][:github_ssl_verify_mode]
      # @param params                [Hash]          Hash containing all options
      #        params[:url]          [String]        Url to target
      #        params[:body]         [JSON]          json data for the request
      #        params[:token]        [String]        OAuth token
      #        params[:username]     [String]        Username if no token specified
      #        params[:password]     [String]        Password if no token specified
      #        params[:request_uri]  [String]        Some request, only need an URI....
      #        params[:action]       [String]        The HTTP action
      #
      url = params[:url]
      action = params[:action]
      token = params[:token]
      username = params[:username]
      password = params[:password]
      body = params[:body]
      request_uri = params[:request_uri] || ''

      unless url || action then
        puts "URL and ACTION not defined!"
        exit 1
      end

      Chef::Log.debug("URL: " + url.to_s)

      url = "#{url}#{request_uri}"
      uri = URI.parse(url)
      http = http_builder.new(uri.host,uri.port)
      if uri.scheme == "https"
        http.use_ssl = true
        if  @ssl_verify_mode == "verify_none"
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        else
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end
      end

      initheader = {}
      if token
        initheader = {"Authorization" => "token #{token}"}
        Chef::Log.debug("Using token: #{token} for action: #{action} on URL: #{url}")
      end

      case action
      when "GET"
        if uri.request_uri.nil?
          req = Net::HTTP::Get.new(uri.path, initheader)
        else
          req = Net::HTTP::Get.new(uri.request_uri, initheader)
        end
      when "POST"
        req = Net::HTTP::Post.new(uri.path, initheader)
      when "DELETE"
        req = Net::HTTP::Delete.new(uri.path, initheader)
      else
        puts "Error, undefined action #{action}"
        exit 1
      end
      if username && password
        req.basic_auth username, password
        Chef::Log.debug("Using basic_auth #{username}, #{password} for action: #{action} on URL: #{url}")
      end

      req.body = body if body
      response = http.request(req)
      validate = response_validator(response)
    end

    def response_validator(response)
      unless response.code =~ /^2../ then
        puts "Error #{response.code}: #{response.message}"
        puts JSON.pretty_generate(JSON.parse(response.body))
        exit 1
      end

      begin
        json = JSON.parse(response.body)
      rescue
        ui.warn "The result on the RESTRequest is not in json format"
        ui.warn "Output: " + response.body
        exit 1
      end
      return json
    end

    def http_builder
      proxy = Chef::Config[:knife][:github_proxy]
      if proxy.nil?
        Net::HTTP
      else
        http_proxy = URI.parse(proxy)
        Chef::Log.debug("Using #{http_proxy.host}:#{http_proxy.port} for proxy")
        user = http_proxy.user if http_proxy.user
        pass = http_proxy.password if http_proxy.password
        Net::HTTP.Proxy(http_proxy.host, http_proxy.port, user, pass)
      end
    end

  end
end

