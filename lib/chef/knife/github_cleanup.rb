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

module KnifeGithubCleanup
  class GithubCleanup < Chef::Knife

      deps do
        require 'chef/knife/github_base'
        include Chef::Knife::GithubBase
        require 'chef/mixin/shell_out'
      end
      
      banner "knife github cleanup [REPO] (options)"
      category "github"

      option :all,
             :short => "-a",
             :long => "--all",
             :description => "Delete all repos from cookbook path.",
             :boolean => true

      option :force,
             :short => "-f",
             :long => "--force",
             :description => "Force deletion even if commits are still present.",
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
          # repo = all_repos.select { |k,v| v["name"] == @cookbook_name }
          repo_cleanup(@cookbook_name)
        elsif config[:all]
          cookbooks.each do |c,v|
            repo_cleanup(c)
          end
        else
          Chef::Log.error("Please specify a repo name")
        end
      end

      def repo_cleanup(repo)
        cookbook_path = config[:cookbook_path] || Chef::Config[:cookbook_path]
        cookbook = File.join(cookbook_path.first,repo)
        if File.exists?(cookbook)
          if repo_status_clean?(cookbook)
            # delete the repo
            puts "here we delete everything :P"
          end
        end
      end

      def repo_status_clean?(repo)
        shell_out!("git fetch", :cwd => repo)
        shell("git status", :cwd => repo)
        return true
      end


      def cookbook_download(repo, cookbook)
        if repo.nil? || repo.empty?
          ui.info("Processing [ ????? ] #{cookbook}")
          Chef::Log.info("Cannot find the repository: #{cookbook} within github")
          return nil
        end

        repo_link = get_repo_clone_link()
        if repo[cookbook].nil? || repo[cookbook][repo_link].nil? || repo[cookbook][repo_link].empty?
          ui.info("Processing [ clean ] #{cookbook}")
          Chef::Log.info("Cannot find the link for the repository with the name: #{cookbook}")
          return nil
        end

 	github_url = repo[cookbook][repo_link]
        cookbook_path = cookbook_path_valid?(cookbook)
        unless cookbook_path.nil?
          ui.info("Processing [ clone ] #{cookbook}")
          Chef::Log.info("Cloning repository to: #{cookbook_path}")
          shell_out!("git clone #{github_url} #{cookbook_path}") 
        end
      end
  
      def cookbook_path_valid?(cookbook_name)
        cookbook_path = config[:cookbook_path] || Chef::Config[:cookbook_path]
        if cookbook_path.nil? || cookbook_path.empty?
          Chef::Log.error("Please specify a cookbook path")
          exit 1
        end

        unless File.exists?(cookbook_path.first) && File.directory?(cookbook_path.first)
          Chef::Log.error("Cannot find the directory: #{cookbook_path.first}")
          exit 1
        end

        cookbook_path = File.join(cookbook_path.first,cookbook_name)
        if File.exists?(cookbook_path)
          ui.info("Processing [ pull  ] #{cookbook_name}")
          Chef::Log.info("Path to #{cookbook_path} already exists, executing pull.")
          shell_out!("git pull", :cwd => cookbook_path)
          return nil
        end
        return cookbook_path
      end

    end
  end
