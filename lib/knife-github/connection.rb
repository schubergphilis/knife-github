require 'json'
require 'uri'
require 'cgi'
require 'openssl'
require 'net/http'

module GithubClient
 class Connection
    def send_get_request(url, params = {})
      unless params.empty?
        params_arr = []
        params.sort.each { |elem|
          params_arr << elem[0].to_s + '=' + CGI.escape(elem[1].to_s).gsub('+', '%20').gsub(' ','%20')
        }
        data = params_arr.join('&')
        url = "#{url}?#{data}"
      end

      #if @github_ssl_verify_mode == "verify_none"
      #  config[:ssl_verify_mode] = :verify_none
      #elsif @github_ssl_verify_mode == "verify_peer"
      #  config[:ssl_verify_mode] = :verify_peer
      #end

      Chef::Log.debug("URL: " + url.to_s)

      uri = URI.parse(url)
      http = http_client_builder.new(uri.host, uri.port)

      if uri.scheme == "https"
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
  
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)

      unless response.is_a?(Net::HTTPOK) then
        puts "Error #{response.code}: #{response.message}"
        puts JSON.pretty_generate(JSON.parse(response.body))
        puts "URL: #{url}"
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

    def http_client_builder
      http_proxy = proxy_uri
      if http_proxy.nil?
        Net::HTTP
      else
        Chef::Log.debug("Using #{http_proxy.host}:#{http_proxy.port} for proxy")
        user = http_proxy.user if http_proxy.user
        pass = http_proxy.password if http_proxy.password
        Net::HTTP.Proxy(http_proxy.host, http_proxy.port, user, pass)
      end
    end

    def proxy_uri
      return nil if @api_proxy.nil?
      result = URI.parse(@api_proxy)
      return result unless result.host.nil? || result.host.empty?
      nil
    end
  end
end
