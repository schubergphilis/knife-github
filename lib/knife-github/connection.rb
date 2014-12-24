require 'json'
require 'uri'
require 'cgi'
require 'openssl'
require 'net/http'

module GithubClient
 class Connection

    def request(params)
      ssl_verify_mode = Chef::Config[:knife][:github_ssl_verify_mode]
      # @param params             [Hash]          Hash containing all options
      #        params[:url]       [String]        Url to target
      #        params[:body]      [JSON]          json data for the request
      #        params[:token]     [String]        OAuth token
      #        params[:username]  [String]        Username if no token specified
      #        params[:password]  [String]        Password if no token specified
      #
      url = params[:url]
      action = params[:action]
      token = params[:token]
      username = params[:username]
      password = params[:password]
      body = params[:body]
      request_uri = params[:request_uri] || ''

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

      if token.nil?
        if action == "GET"
          if uri.request_uri.nil?
            req = Net::HTTP::Get.new(uri.path)
          else
            req = Net::HTTP::Get.new(uri.request_uri)
          end
        elsif action == "POST"
          req = Net::HTTP::Post.new(uri.path)
        elsif action == "DELETE"
          req = Net::HTTP::Delete.new(uri.path)
        end
	if username && password
          req.basic_auth username, password
        end
      else
        if action == "GET"
          if uri.request_uri.nil?
            req = Net::HTTP::Get.new(uri.path, initheader = {"Authorization" => "token #{token}"})
          else
            req = Net::HTTP::Get.new(uri.request_uri, initheader = {"Authorization" => "token #{token}"} )
          end
        elsif action == "POST"
          req = Net::HTTP::Post.new(uri.path, initheader = {"Authorization" => "token #{token}"})
        elsif action == "DELETE"
          req = Net::HTTP::Delete.new(uri.path, initheader = {"Authorization" => "token #{token}"})
        end
      end
      Chef::Log.debug("Using token: #{token} or basic_auth #{username}, #{password} for action: #{action} on URL: #{url}")

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

