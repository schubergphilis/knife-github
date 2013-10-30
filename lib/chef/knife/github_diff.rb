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

class Chef
  class Knife

    class GithubDiff < Knife
    # Implements a diff function between your downloaded copy from git and what is in the Chef Server
    # 
    # By default, it expects that you have already done knife github download COOKBOOK
    #
    # knife github diff cookbook_name [Version]
    # 
    # You can also diff a cookbook against the github version bu using the -g option
    # 
    # You can also optionally give a version on the command line

      deps do
        require 'chef/knife/github_base'

        include Chef::Knife::GithubBase
      end
      
      banner "knife github diff COOKBOOK [version] (options)"
      category "github"

      option :github,
             :short => "-g",
             :long => "--github",
             :description => "Diff against version in github",
             :boolean => true,
             :default => false

      def run
      # The run method.  The entry point into the class

        # validate base options from base module.
        validate_base_options      

        # Display information if debug mode is on.
        display_debug_info

        # Gather all repo information from github.
        get_all_repos = get_all_repos(@github_organizations.reverse)

        # Get all chef cookbooks and versions (hopefully chef does the error handeling).
        cookbooks = rest.get_rest("/cookbooks?num_version=1")

        # Get the cookbook name from the command line
        @cookbook_name = name_args.first unless name_args.empty?
        cookbook_version = name_args[1] unless name_args[1].nil?
        if @cookbook_name
          repo = get_all_repos.select { |k,v| v["name"] == @cookbook_name }
        else
          #repos = all_repos 
          Chef::Log.error("Please specify a cookbook name")
          exit 1
        end
        
        if repo.empty?
          Chef::Log.error("Cannot find the repository: #{} within github")
          exit 1
        end

        github_link = (repo[@cookbook_name][(get_repo_clone_link)])
        if github_link.nil? || github_link.empty?
          Chef::Log.error("Cannot find the link for the repository with the name: #{@cookbook_name}")
          exit 1
        end

        if config[:github]
	        get_clone(github_link, @cookbook_name)
        else # Copy downloaded version to #{@github_tmp}/git
            cpath = cookbook_path_valid?(@cookbook_name, false)
            tpath = "#{@github_tmp}/git"
            if ! File.exists?(tpath)
                FileUtils.makedirs(tpath)
            end
            FileUtils.cp_r cpath, tpath
        end

	    version = get_cookbook_copy(@cookbook_name, cookbook_version)

	    do_diff(@cookbook_name, version)
        FileUtils.remove_entry(@github_tmp)
      end

      def do_diff(name, version)
        # Check to see if there is a tag matching the version
        Dir.chdir("#{@github_tmp}/git/#{name}")
        # Only checkout in github mode
        if config[:github]
            if `git tag`.split("\n").include?(version)
              ui.info("Tag version #{version} found, checking that out for diff")
              # Tag found so checkout that tag
              `git checkout -b #{version}`
              if !$?.exitstatus == 0
                ui.error("Failed to checkout branch #{version}")
                exit 1
              end
            else
              ui.info("Version #{version} of #{name} has no tag, using latest for diff")
            end
        end

        FileUtils.remove_entry("#{@github_tmp}/git/#{name}/.git")
        output = `git diff --color #{@github_tmp}/git/#{name} #{@github_tmp}/cb/#{name}-#{version} 2>&1`
        if output.length == 0
          ui.info("No differences found")
        else
          ui.msg(output)
        end
      end

      def get_cookbook_copy(name, version)
        Dir.mkdir("#{@github_tmp}/cb")
        args = ['cookbook', 'download',  name ]
        args.push version if version
        Dir.chdir("#{@github_tmp}/cb")
        download = Chef::Knife::CookbookDownload.new(args)
        download.config[:download_directory] = "#{@github_tmp}/cb"
        download.run

        Dir.entries("#{@github_tmp}/cb").each do |d|
          if d =~ /#{name}-(.*)/
            version = $1
          end
        end
        return version
      end 

    end
  end
end
