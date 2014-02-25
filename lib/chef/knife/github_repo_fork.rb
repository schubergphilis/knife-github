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

module KnifeGithubRepoFork
  class GithubRepoFork < Chef::Knife
    # Implements the knife github repo fork function
    #
    # == Overview
    # The command will fork the repo into user-space 
    #
    # === Examples
    # Fork a new cookbook:
    #    knife github repo fork <name>
    #
    # === Options
    # -t --github_token		Authentication token for the github.
    #
    
    deps do
      require 'chef/knife/github_base'
      include Chef::Knife::GithubBase
    end
      
    banner "knife github repo fork <name> [owner] [target] (options)"
    category "github"

    option :github_token,
           :short => "-t",
           :long => "--github_token",
           :description => "Your github token for OAuth authentication"

    def run
      params = {}
      # validate base options from base module.
      validate_base_options      

      # Display information if debug mode is on.
      display_debug_info

      # Get the name_args from the command line
      name = name_args[0]
      name_args[1].nil? ? owner = locate_config_value('github_organizations').first : owner = name_args[1]
      target = name_args[2] unless name_args[2].nil?
  
      if owner.nil? || name.nil? || owner.empty? || name.empty? 
        Chef::Log.error("Please specify a repository name like: name ")
        exit 1
      end 

      # Set params for the rest request
      params['url'] = @github_url + "/api/" + @github_api_version + "/repos/#{owner}/#{name}/forks"
      params['body'] = get_body_json(target) unless target.nil?
      params['token'] = get_github_token()
      params['response_code']  = 202

      # Execute the rest request
      username = ENV['USER']

      rest_request(params)
      if target
        puts "Fork of #{name} is created in #{target}"
      else
        puts "Fork of #{name} is created in #{username}"
      end
    end
 
    # Create the json body with repo config for POST information
    # @param target [String] oragnization target name  
    def get_body_json(target)
      body = {
        "organization" => target,
      }.to_json
    end

    # Get the OAuth authentication token from config or command line
    # @param nil
    def get_github_token()
      token = locate_config_value('github_token')
      if token.nil? || token.empty?
        Chef::Log.error("Please specify a github token")
        exit 1
      end
      token
    end

    # Post Get the OAuth authentication token from config or command line
    # @param url   [String] target url (organization or user) 
    #        body  [JSON]   json data with repo configuration
    #        token [String] token sring
    def rest_request(params = {})
      url    = params['url'].to_s
      token  = params['token'].to_s
      code   = params['response_code'] || 200
      body   = params['body'] || nil
      action = params['action'] || 'POST'

      if @github_ssl_verify_mode == "verify_none"
        config[:ssl_verify_mode] = :verify_none
      elsif @github_ssl_verify_mode == "verify_peer"
        config[:ssl_verify_mode] = :verify_peer
      end

      Chef::Log.debug("URL: " + url)

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
       
      req = Net::HTTP::Post.new(uri.path, initheader = {"Authorization" => "token #{token}"})
      req.body = body unless body.nil?
      response = http.request(req)
      
      unless response.code.to_s == code.to_s then
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
      json
    end
  end
end
