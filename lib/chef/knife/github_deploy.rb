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
# This code is specific to our company workflow
# When a cookbook is released it is tagged to a specific version
# This version should match the cookbook version (from the metadata)
# This version is then pinned against specific environments
#
# This class expects you to have committed all your changes to github
# It will then do the rest
# ---------------------------------------------------------------------------- #
require 'chef/knife'

class Chef
  class Knife

    class GithubDeploy < Knife
      deps do
        require 'chef/knife/github_base'

        include Chef::Knife::GithubBase
      end
      
      banner "knife github deploy COOKBOOK VERSION (options)"
      category "github"

      def run

        # validate base options from base module.
        validate_base_options      

        # Display information if debug mode is on.
        display_debug_info

        # Gather all repo information from github.
        get_all_repos = get_all_repos(@github_organizations.reverse)

        # Get all chef cookbooks and versions (hopefully chef does the error handeling).
        cookbooks = rest.get_rest("/cookbooks?num_version=1")

        @versions = []
        @cookbook_name = name_args.first unless name_args.empty?
        cookbook_version = name_args[1] unless name_args[1].nil?

        # Could build a selector based upon what is in github but that seems
        # a little circular ....
        if ! cookbook_version
          Chef::Log.error("You must specify a version to be able to deploy")
          exit 1
        end

        if @cookbook_name
          repo = get_all_repos.select { |k,v| v["name"] == @cookbook_name }
        else
          Chef::Log.error("Please specify a cookbook name")
          exit 1
        end
        if repo.nil?
          Chef::Log.error("Cannot find the repository: #{} within github")
          exit 1
        end

        github_link = get_github_link(repo[@cookbook_name])
        if github_link.nil? || github_link.empty?
          Chef::Log.error("Cannot find the github link for the repository with the name: #{@cookbook_name}")
          exit 1
        end
		get_clone(github_link, @cookbook_name)
        # Now try and check the tag out - moan if that is not possible
        checkout_tag(cookbook_version)

        github_version = get_cookbook_version()
        get_cookbook_chef_versions()
        while true do
                if @versions.include?(cookbook_version)
                   ui.info("Version #{cookbook_version} is already in chef")
                   ui.confirm("Shall I change the version (No to Cancel)")
                end
        end

        if repo[@cookbook_name]['tags'].select { |k| k['name'] == cookbook_version }.empty?
            # TODO:  Option to Create the tag
            Chef::Log.error("Version #{@cookbook_name} for Cookbook #{@cookbook_name} is not tagged in github")
            exit 1
        end


        # If we have gotten this far we can just upload the cookbook
        cookbook_upload()
        FileUtils.remove_entry(@github_tmp)

      end

      def choose_version()
      end
      def cookbook_upload() 
          ui.info "Upload Cookbook to Chef server"
		  args = ['cookbook', 'upload',  @cookbook_name ]
          upload = Chef::Knife::CookbookDownload.new(args)
          upload.config[:cookbook_path] = "#{@github_tmp}/git"
          # plugin will throw its own errors
          upload.run
      end

      def checkout_tag(version)
          Dir.chdir("#{@github_tmp}/git/#{@cookbook_name}")
		  `git checkout -b #{version}`
		  if !$?.exitstatus == 0
		     ui.error("Failed to checkout branch #{version} of #{@cookbook_name}")
		     exit 1
          end
          # Git meuk should not be uploaded
          FileUtils.remove_entry("#{@github_tmp}/git/#{@cookbook_name}/.git")
      end

      def get_cookbook_chef_versions ()
          cookbooks = rest.get_rest("/cookbooks/#{@cookbook_name}?num_version=all")
          cookbooks[@cookbook_name]['versions'].each do |v|
              @versions.push v['version']
          end
      end

      # ---------------------------------------------------------------------- #
      # Get the version number in the git version of the cookbook
      # ---------------------------------------------------------------------- #
      def get_cookbook_version()
          version = nil
          File.foreach("#{@github_tmp}/git/#{@cookbook_name}/metadata.rb") do |line|
              if line =~ /version.*"(.*)"/i
                 version = $1
                 break
              end
          end
          if version.nil?
             Chef::Log.error("Cannot get the version for cookbook #{@cookbook_name} in github")
             exit 1
          end
          version
      end

    end
  end
end
