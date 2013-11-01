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


#
#
#  BE AWARE THIS COMMAND IS STILL UNDER HEAVY DEVELOPMENT!
#
#
require 'chef/knife'

module KnifeGithubCreate
  class GithubCreate < Chef::Knife

    deps do
      require 'chef/knife/github_base'
      include Chef::Knife::GithubBase
      require 'chef/mixin/shell_out'
    end
      
    banner "knife github create STRING (options)"
    category "github"

    option :github_token,
           :short => "-t",
           :long => "--github_token",
           :description => "Your githb token for authentication"

    def run
      extend Chef::Mixin::ShellOut

      # validate base options from base module.
      validate_base_options      

      # Display information if debug mode is on.
      display_debug_info

      # Get the name_args from the command line
      name = name_args.first

      # Get the organization name from config
      org = locate_config_value('github_organizations').first

      if name.nil? || name.empty? 
        Chef::Log.error("Please specify a repository name")
        exit 1
      end 
      
      token = get_github_token()
      
      url = @github_url + "/api/" + @github_api_version + "/user/repos"

      # Get body data 
      body = get_body_json(name)

      Chef::Log.debug("Creating the repository on github in organization: #{org}")
      repo = post_request(url, body, token)

      Chef::Log.debug("Creating the local repository based on template")
      create_cookbook(name)

      cpath = cookbook_path_valid?(name, false)
      gitlink = repo['ssh_url']

      #shell_out!("git fetch", :cwd => cookbook)
      #status = shell_out!("git status", :cwd => cookbook)
      #unless status.stdout == "# On branch master\nnothing to commit (working directory clean)\n"

      shell_out!("git init", :cwd => cpath )
      shell_out!("git add .", :cwd => cpath ) 
      shell_out!("git commit -m 'creating the initial cookbook structure from knife-github' ", :cwd => cpath ) 
      shell_out!("git remote add origin #{gitlink} ", :cwd => cpath ) 
      shell_out!("git push -u origin master", :cwd => cpath ) 
    end
    
    def create_cookbook(name)
      args = [ name ]
      create = Chef::Knife::CookbookCreate.new(args)
      # create.config[:download_directory] = "#{@github_tmp}/cb"
      create.run
    end
  
    def get_body_json(name)
      body = {
        "name" => name,
        "description" => "We should ask for an description",
        "private" => false,
        "has_issues" => true,
        "has_wiki" => true,
        "has_downloads" => true
      }.to_json
    end

    def get_github_token()
      token = locate_config_value('github_token')

      if token.nil? || token.empty?
        Chef::Log.error("Please specify a github token")
        exit 1
      end
      return token
    end

    def post_request(url, body, token)

      if @github_ssl_verify_mode == "verify_none"
        config[:ssl_verify_mode] = :verify_none
      elsif @github_ssl_verify_mode == "verify_peer"
        config[:ssl_verify_mode] = :verify_peer
      end

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
       
      req = Net::HTTP::Post.new(uri.path, initheader = {"Authorization" => "token #{token}"})
      req.body = body        
      response = http.request(req)
      
      unless response.code == "201" then
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
  end
end
