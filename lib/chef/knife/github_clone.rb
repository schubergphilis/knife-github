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

  module KnifeGitHubClone

    # Clones a cookbook version to your local cookbooks directory
    #
    class GithubClone < Chef::Knife

      deps do
        require 'chef/knife/github_base'
        include Chef::Knife::GithubBase
        require 'chef/mixin/shell_out'
      end

      banner "knife github clone COOKBOOK (options)"
      category "github"

      option :all,
             :short => "-a",
             :long => "--all",
             :description => "Clone all repo's from github.",
             :boolean => true

      option :force,
             :short => "-f",
             :long => "--force",
             :description => "Delete the existing local repo if exist.",
             :boolean => true

      def run

        #executing shell commands
	extend Chef::Mixin::ShellOut

        # validate base options from base module.
        validate_base_options

        # Display information if debug mode is on.
        display_debug_info

        # Gather all repo information from github.
        all_repos = get_all_repos(@github_organizations.reverse)

        # Get all chef cookbooks and versions (hopefully chef does the error handeling).
        cookbooks = rest.get_rest("/cookbooks?num_version=1")

        # Get the cookbook names from the command line
        @cookbook_name = name_args.first unless name_args.empty?
        if @cookbook_name
          repo = all_repos.select { |k,v| v["name"] == @cookbook_name }
          repo_clone(repo, @cookbook_name)
        elsif config[:all]
          cookbooks.each do |c,v|
            repo_clone(all_repos, c)
          end
        else
          Chef::Log.error("Please specify a repository name")
        end
      end

      def repo_clone(repo, cookbook_name)
        if repo.nil? || repo.empty?
          ui.info("Processing [ UNKNOWN ] #{cookbook_name}")
          Chef::Log.info("Cannot find the repository: #{cookbook_name} within github")
          return nil
        end

        repo_link = get_repo_clone_link()
        if repo[cookbook_name].nil? || repo[cookbook_name][repo_link].nil? || repo[cookbook_name][repo_link].empty?
          ui.info("Processing [ UNKNOWN ] #{cookbook_name}")
          Chef::Log.info("Cannot find the link for the repository with the name: #{cookbook_name}")
          return nil
        end

 	github_url = repo[cookbook_name][repo_link]
        token = get_github_token
        if token.nil? || token.empty?
          clone_url = github_url
        else
          uri = URI.parse(github_url)
          uri.userinfo = "#{token}:x-oauth-basic"
          clone_url = URI.join(uri)
        end
        cookbook_path = get_cookbook_path(cookbook_name)
        if File.exists?(cookbook_path)
          ui.info("Processing [ SKIP    ] #{cookbook_name}")
          Chef::Log.info("Path to #{cookbook_path} already exists, skipping.")
        else
          ui.info("Processing [ CLONE   ] #{cookbook_name}")
          Chef::Log.info("Cloning repository to: #{cookbook_path}")
          Chef::Log.debug("Using url: #{clone_url}")
          shell_out!("git clone #{clone_url} #{cookbook_path}")
        end
      end

  end
end
