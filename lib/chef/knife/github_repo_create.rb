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

module KnifeGithubRepoCreate
  class GithubRepoCreate < Chef::Knife
    # Implements the knife github repo create function
    #
    # == Overview
    # The command will create a empty cookbook structure and it will commit this one into the github.
    #
    # === Examples
    # Create a new cookbook:
    #    knife github repo create <name> <here you give your cookbook description>
    #
    #   #  Deploy a release version of cookbook to your chef server
    #   #     knife github deploy cookbook_name -f
    #
    # === Options
    # -t --github_token		Authentication token for the github.
    # -U --github_user_repo	Create the cookbook in the user environment.
    #
    
    deps do
      require 'chef/knife/github_base'
      include Chef::Knife::GithubBase
      require 'chef/mixin/shell_out'
      require 'readline'
    end
      
    banner "knife github repo create <name> <description> (options)"
    category "github"

    option :github_token,
           :short => "-t",
           :long => "--github_token",
           :description => "Your github token for OAuth authentication"

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
      name = name_args.first
      name_args.shift

      # Get the organization name from config
      org = locate_config_value('github_organizations').first

      if name.nil? || name.empty? 
        Chef::Log.error("Please specify a repository name")
        exit 1
      end 
       
      desc = get_repo_description
      type = get_repo_type

      if config[:github_user_repo]
        url = @github_url + "/api/" + @github_api_version + "/user/repos"
        Chef::Log.debug("Creating repository in user environment")
      else
        url = @github_url + "/api/" + @github_api_version + "/orgs/#{org}/repos"
        Chef::Log.debug("Creating repository in organization: #{org}")
      end

      @github_tmp = locate_config_value("github_tmp") || '/var/tmp/gitcreate'
      @github_tmp = "#{@github_tmp}#{Process.pid}"

      # Get token information
      token = get_github_token()

      # Get body data for post
      body = get_body_json(name, desc)

      # Creating the local repository or using existing one.
      cookbook_dir = get_cookbook_path(name) || ""

      if File.exists?(cookbook_dir)
        Chef::Log.debug("Using local repository from #{cookbook_dir}")

        # Creating the github repository
        Chef::Log.debug("Creating the github repository")
        repo = post_request(url, body, token)
        github_ssh_url = repo['ssh_url']
    
        Chef::Log.debug("Commit and push local repository")
        # Initialize the local git repo
        git_commit_and_push(cookbook_dir, github_ssh_url)

        puts "Finished creating #{name} and uploading #{cookbook_dir}"
      else
        Chef::Log.debug("Creating the repository based on #{type} template")
        create_cookbook(name, type, @github_tmp)
  
        cookbook_dir = File.join(@github_tmp, name)
  
        # Updateing template information if needed.
        update_template_files(name, cookbook_dir, desc)
  
        # Creating the github repository
        Chef::Log.debug("Creating the github repository")
        repo = post_request(url, body, token)
        github_ssh_url = repo['ssh_url']
  
        Chef::Log.debug("Commit and push local repository")      
        # Initialize the local git repo
        git_commit_and_push(cookbook_dir, github_ssh_url)
  
        Chef::Log.debug("Removing temp files")
        FileUtils.remove_entry(@github_tmp)
        puts "Finished creating and uploading #{name}"
      end
    end

 
    # User selection on repo description
    # @return [string]
    def get_repo_description
      question = "\nPlease enter a description for the repository: "

      desc = input question
      if desc.nil? || desc.empty?
        Chef::Log.error("Please enter a repository description")
        get_repo_description
      end
      desc
    end

    # User selection on repo type 
    # @return [string]
    def get_repo_type
      question = "\nPlease select the repository type that you want to create.\n"
      question += "  1 - Empty\n"
      question += "  2 - Cookbook Application\n"
      question += "  3 - Cookbook Wrapper\n"
      question += "  4 - Cookbook Role\n"
      question += "Type: "

      type = input question
      case type
        when '1'
          return 'empty'
        when '2'
          return "application"
        when '3'
          return "wrapper"
        when '4'
          return "role"
        else
          Chef::Log.error("Please select 1-4 to continue.")
          get_repo_type
      end
    end

    # Read the commandline input and return the input
    # @param prompt [String] info to prompt to user
 
   $stdout.sync = false
    def input(prompt="", newline=true)
      prompt += "\n" if newline
      Readline.readline(prompt).squeeze(" ").strip
    end

    # Set the username in README.md
    # @param cookbook_path [String] cookbook path
    #        github_ssh_url [String] github ssh url from repo
    def git_commit_and_push(cookbook_path, github_ssh_url)
      if File.exists?(File.join(cookbook_path, ".git"))
        shell_out("git remote rm origin", :cwd => cookbook_path)
      else  
        shell_out!("git init", :cwd => cookbook_path)
      end
      shell_out!("echo - $(date): Uploaded with knife github plugin. >> CHANGELOG.md ", :cwd => cookbook_path)
      shell_out!("git add .", :cwd => cookbook_path) 
      shell_out!("git commit -m 'creating initial cookbook structure from the knife-github plugin' ", :cwd => cookbook_path) 
      shell_out!("git remote add origin #{github_ssh_url} ", :cwd => cookbook_path) 
      shell_out!("git push -u origin master", :cwd => cookbook_path) 
    end

    # Update all template files with the right information
    # @param name [String] cookbook path    
    def update_template_files(name, cookbook_path, description)
      files = Dir.glob("#{cookbook_path}/**/*").select{ |e| File.file? e }
      user    = get_username || "Your Name" 
      email   = get_useremail || "Your Email"
      company = "Schuberg Philis"
      year    = Time.now.year
      date    = Time.now
      files.each do |file|
        contents = ""
        File.foreach(file) do |line|
          line.gsub!(/DESCRIPTION/, description)
          line.gsub!(/COOKBOOK/, name)
          line.gsub!(/COMPANY/, company)
          line.gsub!(/NAME/, user)
          line.gsub!(/EMAIL/, email)
          line.gsub!(/YEAR/, year.to_s)
          line.gsub!(/DATE/, date.to_s)
          contents += line
        end
        File.open(file, 'w') {|f| f.write(contents) }
      end
      return nil
    end

    # Get the username from passwd file or git config
    # @param nil
    def get_username()
      username = ENV['USER']
      passwd_user = %x(getent passwd #{username} | cut -d ':' -f 5).chomp
      username = passwd_user if passwd_user
      git_user_name = %x(git config user.name).strip
      username = git_user_name if git_user_name
      username
    end

    # Get the email from passwd file or git config
    # @param nil
    def get_useremail()
      email = nil
      git_user_email = %x(git config user.email).strip
      email = git_user_email if git_user_email
      email
    end

    # Create the cookbook template for upload
    # @param name [String] cookbook name
    #        type [String] type of cookbook
    #        tmp  [String] temp location
    def create_cookbook(name, type, tmp)
      target = File.join(tmp, name)
      template_org = locate_config_value("github_template_org")
      if template_org.nil? || template_org.empty?
        Chef::Log.fatal("Cannot find github_template_org within your configuration")  
      else

        github_url = @github_url.gsub('http://', 'git://') if @github_url =~ /^http:\/\/.*$/
        github_url = @github_url.gsub('https://', 'git://') if @github_url =~ /^https:\/\/.*$/
 
        template_path = File.join(github_url, template_org, "chef_template_#{type}.git") 
        shell_out!("git clone #{template_path} #{target}") # , :cwd => cookbook_path)
      end
    end

    # Create the json body with repo config for POST information
    # @param name [String] cookbook name  
    def get_body_json(cookbook_name, description="Please fill in the description.")
      body = {
        "name" => cookbook_name,
        "description" => description,
        "private" => false,
        "has_issues" => true,
        "has_wiki" => true,
        "has_downloads" => true
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
      json
    end
  end
end
