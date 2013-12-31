#
# Author:: Sander Botman (<sbotman@schubergphilis.com>)
# Copyright:: Copyright (c) 2013 Sander Botman.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/knife'

module KnifeGithubTokenCreate
  class GithubTokenCreate < Chef::Knife
    # Implements the knife github token create function
    #
    # == Overview
    # The command will create a authorization token in order to communicate with the github enterprise appliance.
    #
    # === Examples
    # Create a new token:
    #    knife github token create <username>
    #
    #   #  Deploy a release version of cookbook to your chef server
    #   #     knife github deploy cookbook_name -f
    #
    # === Options
    # -t --github_token		Authentication token for the github.
    # -U --github_user_repo	Create the cookbook in the user environment.
    #
    
    deps do
      require 'knife-github/password'
      require 'chef/knife/github_base'
      include Chef::Knife::GithubBase
      require 'chef/mixin/shell_out'
    end
      
    banner "knife github token create <username> (options)"
    category "github"

    option :force,
           :short => "-f",
           :long => "--force",
           :description => "Force token creation for OAuth authentication",
           :boolean => true

    option :github_user_repo,
           :short => "-U",
           :long => "--github_user_repo",
           :description => "Create the repo within your user environment",
           :boolean => true

    def run
      extend Chef::Mixin::ShellOut

      # validate base options from base module.
      validate_base_options      

      # Display information if debug mode is on.
      display_debug_info

      # Get the name_args from the command line
      username = name_args.first

      # Get token information
      token = get_github_token() unless config[:force]

      # Create github token if needed
      if token.nil?
        token = validate_github_token(username)
        update_knife_config(token)
      end

      puts "Finished updating your token. Using key:#{token}"
    end
 
    # Updates the knife configuration with the token information inside ~/.chef/knife.rb
    # @param token [String] token key
    # 
    def update_knife_config(token)
      contents = ''
      update = false
      config   = File.join(ENV["HOME"], ".chef/knife.rb")
      File.foreach(config) do |line|
        if line =~ /^\s*knife\[:github_token\].*/ && !token.nil?
          Chef::Log.debug("Replacing current token with: #{token}")
          contents = contents << "knife[:github_token] = \"#{token}\"\n"
          update = true
        else 
          contents = contents << line
        end
      end
      unless update
        Chef::Log.debug("Updating configuration with token: #{token}")
        contents = contents << "knife[:github_token] = \"#{token}\"\n"
      end
      File.open(config, 'w') {|f| f.write(contents) }
      return true
    end

    # Get the OAuth authentication token from config or command line
    # @param none
    def get_github_token()
      token = locate_config_value('github_token')
      if token.nil? || token.empty? 
        return nil
      else
        return token
      end
    end

    # Validate the OAuth authentication token for the knife-github application.
    # @param username   [String]        validates the token for specific user. (default is ENV['USER'])
    #
    def validate_github_token(username=nil)
      params = {}
      username = ENV["USER"] if username.nil?

      params[:url] = @github_url + "/api/" + @github_api_version + "/authorizations"
      Chef::Log.debug("Validating token information for user: #{username}.")

      params[:username] = username
      params[:password] = Github::Password.get( "Please enter github password for #{username} :" )
      params[:action]   = "GET"

      token_key = nil

      result = send_request(params)
      result.each do |token|
        if token['app'] && token['app']['name'] == "knife-github (API)"
          if token['scopes'].include?("delete_repo")
            Chef::Log.debug("Found and using token: #{token_key}")
            token_key = token['token']
          else
            Chef::Log.debug("Found token: #{token_key} but wrong scope, deleting token.")
            params[:id] = token['id']
            delete_github_token(params)
          end
        end
      end

      if token_key.nil?
        result = create_github_token(params)
        token_key = result['token']        
      end

      return token_key
    end
 

    # Create the OAuth authentication token for the knife-github application.
    # @param params             [Hash]          Hash containing all options
    #        params[:username]  [String]        Username if no token specified
    #        params[:password]  [String]        Password if no token specified
    #
    def create_github_token(params)
      Chef::Log.debug("Creating new application token for user: #{username}.")
      params[:url]    = @github_url + "/api/" + @github_api_version + "/authorizations"
      params[:body]   = '{"note":"knife-github","scopes":["delete_repo", "user", "public_repo", "repo", "gist"]"}'
      params[:action] = "POST"
      send_request(params)
    end

    def delete_github_token(params)
      Chef::Log.debug("Deleting token id: #{params[':id']}")
      params[:url]    = @github_url + "/api/" + @github_api_version + "/authorizations/#{params[:id]}"
      params[:action] = "DELETE"
      send_request(params)
    end

    # Post Get the OAuth authentication token from config or command line
    # @param params		[Hash] 		Hash containing all options 
    #        params[:url]	[String]	Url to target
    #        params[:body]  	[JSON]   	json data for the request
    #        params[:token]	[String] 	OAuth token
    #        params[:username]	[String]	Username if no token specified
    #        params[:password]  [String]	Password if no token specified
    #
    def send_request(params)
      url = params[:url]
      
      Chef::Log.debug("URL: " + url.to_s)

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host,uri.port)
      if uri.scheme == "https"
        http.use_ssl = true
        if  @github_ssl_verify_mode == "verify_none"
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        else
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end
      end

      if params[:action] == "GET"
        req = Net::HTTP::Get.new(uri.path)
      elsif params[:action] == "POST"
        req = Net::HTTP::Post.new(uri.path)
      elsif params[:action] == "DELETE" 
        req = Net::HTTP::Delete.new(uri.path)
      end
      
      if params[:token].nil?
        req.basic_auth params[:username], params[:password]
      else
        req.initheader = ({"Authorization" => "token #{params[:token]}"})
      end
      req.body = params[:body] if params[:body]
      response = http.request(req)
      
      unless response.code =~ /^2../ then
        puts "Error #{response.code}: #{response.message}"
        puts JSON.pretty_generate(JSON.parse(response.body))
        puts "URL: #{url}"
        exit 1
      end

      return nil if response.body.nil? || response.body.empty?

      begin
        json = JSON.parse(response.body)
      rescue
        ui.warn "The result on the REST Request is not in json format"
        ui.warn "Output: " + response.body
        exit 1
      end
      json
    end
  end
end
