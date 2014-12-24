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
    
    deps do
      require 'chef/knife/github_base'
      include Chef::Knife::GithubBase
    end
      
    banner "knife github repo fork <name> [owner] [target] (options)"
    category "github"

    def run
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
      params = {}
      params[:url] = @github_url + "/api/" + @github_api_version + "/repos/#{owner}/#{name}/forks"
      params[:body] = get_body_json(target) unless target.nil?
      params[:token] = get_github_token()
      #params[:response_code]  = 202
      params[:action]  = "POST"

      # Execute the rest request
      username = ENV['USER']

      connection.request(params)
      if target
        puts "Fork of #{name} is created in #{target}"
      else
        puts "Fork of #{name} is created in #{username}"
      end
    end
 
  end
end
