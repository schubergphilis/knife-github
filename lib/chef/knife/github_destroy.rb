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
require 'etc'

module KnifeGithubDestroy
  class GithubDestroy < Chef::Knife
    # Implements the knife github destroy function
    #
    # == Overview
    # The command will delete and destroy a cookbook repo on GitHub.
    #
    # === Examples
    # Destroy a repository:
    #    knife github destroy COOKBOOK (options)
    #
    # === Options
    # -U --github_user_repo	Destroy the cookbook in the user environment
    #

    deps do
      require 'chef/knife/github_base'
      include Chef::Knife::GithubBase
      require 'chef/mixin/shell_out'
    end

    banner 'knife github destroy COOKBOOK (options)'
    category "github"

    option :github_user_repo,
           :short => "-U",
           :long => "--github_user_repo",
           :description => "Destroy the cookbook in the user environment",
           :boolean => true

    def run
      extend Chef::Mixin::ShellOut

      # validate base options from base module.
      validate_base_options

      # Display information if debug mode is on.
      display_debug_info

      # Get the repo name from the command line
      name = name_args.first

      # Get the organization name from config
      org = locate_config_value('github_organizations').first

      if name.nil? || name.empty?
        Chef::Log.error("Please specify a repository name")
        exit 1
      end

      user = get_userlogin

      if config[:github_user_repo]
        url = @github_url + "/api/" + @github_api_version + "/repos/#{user}/#{name}"
        Chef::Log.debug("Destroying repository in user environment: #{user}")
      else
        url = @github_url + "/api/" + @github_api_version + "/repos/#{org}/#{name}"
        Chef::Log.debug("Destroying repository in organization: #{org}")
      end

      # @github_tmp = locate_config_value("github_tmp") || '/var/tmp/gitcreate'
      # @github_tmp = "#{@github_tmp}#{Process.pid}"

      # Get token information
      token = get_github_token()

      # Get body data for post
      # body = get_body_json(name, desc)

      # Creating the local repository
      # Chef::Log.debug("Creating the local repository based on template")
      # create_cookbook(name, @github_tmp)

      # cookbook_path = File.join(@github_tmp, name)

      # Updating README.md if needed.
      # update_readme(cookbook_path)

      # Updateing metadata.rb if needed.
      # update_metadata(cookbook_path)

      # Deleting the github repository
      params = {}
      params[:url] = url
      params[:token] = token
      params[:action] = "DELETE"
      repo = connection.request(params)
      puts "Repo: #{name} is deleted" if repo.nil?

      # github_ssh_url = repo['ssh_url']

      # Chef::Log.debug("Commit and push local repository")
      # Initialize the local git repo
      # git_commit_and_push(cookbook_path, github_ssh_url)

      # Chef::Log.debug("Removing temp files")
      # FileUtils.remove_entry(@github_tmp)
    end

    # Set the username in README.md
    # @param cookbook_path [String] cookbook path
    #        github_ssh_url [String] github ssh url from repo
    def git_commit_and_push(cookbook_path, github_ssh_url)
      shell_out!("git init", :cwd => cookbook_path )
      shell_out!("git add .", :cwd => cookbook_path )
      shell_out!("git commit -m 'creating initial cookbook structure from the knife-github plugin' ", :cwd => cookbook_path )
      shell_out!("git remote add origin #{github_ssh_url} ", :cwd => cookbook_path )
      shell_out!("git push -u origin master", :cwd => cookbook_path )
    end

    # Set the username in README.md
    # @param name [String] cookbook path
    def update_readme(cookbook_path)
      contents = ''
      username = get_username
      readme = File.join(cookbook_path, "README.md")
      File.foreach(readme) do |line|
        line.gsub!(/TODO: List authors/,"#{username}\n")
        contents = contents << line
      end
      File.open(readme, 'w') {|f| f.write(contents) }
      return nil
    end

    # Set the username and email in metadata.rb
    # @param name [String] cookbook path
    def update_metadata(cookbook_path)
      contents = ''
      username = get_username
      email    = get_useremail
      metadata = File.join(cookbook_path, "metadata.rb")
      File.foreach(metadata) do |line|
        line.gsub!(/YOUR_COMPANY_NAME/,username) if username
        line.gsub!(/YOUR_EMAIL/,email) if email
        contents = contents << line
      end
      File.open(metadata, 'w') {|f| f.write(contents) }
      return nil
    end

    # Get the username from git config otherwise fall back to passwd file
    # @param nil
    def get_username()
      username_gitconfig = %x(git config user.name).strip
      username_passwd    = Etc.getpwnam(Etc.getlogin).gecos.gsub(/ - SBP.*/,'')

      username = username_gitconfig unless username_gitconfig.nil?
      username = username_passwd if username.empty?
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

    # Get the email from passwd file or git config
    # @param nil
    def get_userlogin()
      email = get_useremail()
      unless email
        puts "Cannot continue without login information. Please define the git email address."
        exit 1
      end
      login = email.split('@').first
    end


    # Create the cookbook template for upload
    # @param name [String] cookbook name
    #        tmp  [String] temp location
    def create_cookbook(name, tmp)
      args = [ name ]
      create = Chef::Knife::CookbookCreate.new(args)
      create.config[:cookbook_path] = tmp
      create.run
    end
  end
end
