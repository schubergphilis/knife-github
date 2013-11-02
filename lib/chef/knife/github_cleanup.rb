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
# ---------------------------------------------------------------------------- #
# Abstract
# ---------------------------------------------------------------------------- #
# This code is intended to help you cleaning up your locate repo's.
# It will check if your repo if insync with the github and will not touch if
# this is not the case. Then it will check if you have any branches local
# and not on the github.
#
# If it cannot find any uncommitted changes, it will safely remove your repo.
# It's good practice to cleanup and re-download repos because this way they 
# can move from organization to organization.
# ---------------------------------------------------------------------------- #
#
require 'chef/knife'

module KnifeGithubCleanup
  class GithubCleanup < Chef::Knife

  deps do
    require 'chef/knife/github_base'
      include Chef::Knife::GithubBase
      require 'chef/mixin/shell_out'
    end
    
    banner "knife github cleanup [COOKBOOK] (options)"
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
        if repo_status_clean?(repo, cookbook)
          # delete the repo 
          ui.info("Processing [ DELETE  ] #{repo}")
          FileUtils.remove_entry(cookbook) 
        end
      else
        puts "cannot find repo path for: #{repo}" unless config[:all]
      end
    end

    def repo_status_clean?(repo, cookbook)
      shell_out!("git fetch", :cwd => cookbook)
      status = shell_out!("git status", :cwd => cookbook)
      unless status.stdout == "# On branch master\nnothing to commit (working directory clean)\n"
        ui.info("Processing [ COMMIT  ] #{repo} (Action needed!)")
        status.stdout.lines.each { |l| puts l.sub( /^/, "    ") }
        return false   
      end
      log = shell_out!("git log --branches --not --remotes --simplify-by-decoration --decorate --oneline", :cwd => cookbook)
      unless log.stdout.empty?
        ui.info("Processing [ BRANCH  ] #{repo} (Action needed!)")
        ui.info("    Please check your branches, one of them has unsaved changes")
        log.stdout.lines.each { |l| puts l.sub( /^/, "    ") }
        return false   
      end
      return true
    end
  end
end
