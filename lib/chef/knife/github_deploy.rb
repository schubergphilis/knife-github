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
# This class expects you to have pushed all your changes to github
# It will then do the rest
#
# There are two modes of operation
# Development (default)
#
# This will take a cookbook name find it, clone it and upload it to your
# chef server.
#
# If the cookbook is frozen it will force you to choose a new version
# and update the metadata accordingly
#
# Final (-f)
#
# You will be forced to select a new version.
# You can choose via the options whether to increment the Major/minor or patch
# revision numbers
# The version will be tagged
# Uploaded to the Chef server and frozen
#
# Version numbers
#
# You can choose a specific version number by specifying it on the command
# line.
#
# If you do not specify a version, the version of the last tag in github
# will be used
#
# If there is no tag, a version number must be given on the command line
# ---------------------------------------------------------------------------- #
require 'chef/knife'

class Chef
  class Knife

    class GithubDeploy < Knife
      deps do
        require 'chef/knife/github_base'
        include Chef::Knife::GithubBase
        require 'chef/cookbook_loader'
        require 'chef/cookbook_uploader'
      end
      
      banner "knife github deploy COOKBOOK [VERSION] (options)"
      category "github"

      option :final,
             :short => "-f",
             :long => "--final",
             :description => "Bump version, make git tag and freeze",
             :boolean => true,
             :default => false

      option :major,
             :short => "-M",
             :long => "--major",
             :description => "In final mode, increase the major version ie. X.x.x",
             :boolean => true,
             :default => false

      option :minor,
             :short => "-m",
             :long => "--minor",
             :description => "In final mode, increase the minor version ie. x.X.x",
             :boolean => true,
             :default => false

      option :patch,
             :short => "-p",
             :long => "--patch",
             :description => "In final mode, increase the minor version ie. x.x.X (Default)",
             :boolean => true,
             :default => true

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
        cookbook_version = nil
        @cookbook_name = name_args.first unless name_args.empty?
        cookbook_version = name_args[1] unless name_args[1].nil?

        if @cookbook_name
          repo = get_all_repos.select { |k,v| v["name"] == @cookbook_name }
        else
          Chef::Log.error("Please specify a cookbook name")
          exit 1
        end

        if repo.empty?
          Chef::Log.error("Cannot find the repository: #{@cookbook_name} within github")
          exit 1
        end

        # We could also interrogate the metadata.rb in the master version to get this
        # That would mean making this check much later on in the code
        if ! cookbook_version && get_all_repos[@cookbook_name]['latest_tag'].nil?
          Chef::Log.error("I cannot determine the latest version")
          Chef::Log.error("You must specify a version to be able to deploy")
          exit 1
        elsif ! cookbook_version
            cookbook_version = get_all_repos[@cookbook_name]['latest_tag']
            ui.info "Using " << get_all_repos[@cookbook_name]['latest_tag'] << " as version"
        end
        github_link = get_github_link(repo[@cookbook_name])
        if github_link.nil? || github_link.empty?
          Chef::Log.error("Cannot find the github link for the repository with the name: #{@cookbook_name}")
          exit 1
        end

        inChef = true
        isFrozen = false
        if (config[:major] || config[:minor])
            config[:patch] = false
        end

        begin
            isFrozen = rest.get_rest("cookbooks/#{@cookbook_name}/#{cookbook_version}").frozen_version?
        rescue
            ui.warn "#{@cookbook_name} is not yet in chef"
            inChef = false
        end

        
        if config[:final]
            ui.info "Using Final mode"
        else
            ui.info "Using Development mode"
        end

		get_clone(github_link, @cookbook_name)

        # Might be first upload so need to catch that cookbook does not exist!
        get_cookbook_chef_versions()  unless ! inChef

        ui.info "Cookbook is frozen" if isFrozen
        if config[:final]
            cookbook_version = up_version(cookbook_version)

            if repo[@cookbook_name]['tags'].select { |k| k['name'] == cookbook_version }.empty?
                ui.info("Cookbook #{cookbook_version} has no tag in Git")
                ui.confirm("Shall I add a tag for you?")
                set_cookbook_version(cookbook_version)
                add_tag(cookbook_version)
            else
                checkout_tag(cookbook_version)
                set_cookbook_version(cookbook_version)
            end

            do_commit(cookbook_version)
        end

        # In Dev mode the version of the cookbook does not need to change
        # If however the cookbook is frozen, then the version has to change
        if ! config[:final] && isFrozen
            cookbook_version = up_version(cookbook_version)
            set_cookbook_version(cookbook_version)
            do_commit(cookbook_version)
        end

        # If we have gotten this far we can just upload the cookbook
        cookbook_upload()
        FileUtils.remove_entry(@github_tmp)

      end

      def up_version(version)
          while true do
                ui.info("Trying to deploy version #{version}")
                if @versions.include?(version)
                   ui.info("Version #{version} is already in chef")
                   ui.confirm("Shall I bump the version (No to Cancel)")
                   version = choose_version(version)
                else
                   break
                end
          end
          version
      end

      def choose_version(version)
          if version =~ /(\d+)\.(\d+)\.(\d+)/
             major = $1
             minor = $1
             patch = $3
             major = major.to_i + 1 if config[:major]
             minor = minor.to_i + 1 if config[:minor]
             patch = patch.to_i + 1 if config[:patch]
             version = "#{major}.#{minor}.#{patch}"
             Chef::Log.debug("New version is #{version}")
          else
             Chef::Log.error("Version is in a format I cannot auto auto-update")
             exit 1
          end
          version
      end

      def cookbook_upload() 
          # Git meuk should not be uploaded
          FileUtils.remove_entry("#{@github_tmp}/git/#{@cookbook_name}/.git")
		  args = ['cookbook', 'upload',  @cookbook_name ]
          if config[:final]
              args.push "--freeze"
          end
          upload = Chef::Knife::CookbookUpload.new(args)
          upload.config[:cookbook_path] = "#{@github_tmp}/git"
          # plugin will throw its own errors
          upload.run
      end

      def checkout_tag(version)
          ui.info "Checking out tag #{version}"
          Dir.chdir("#{@github_tmp}/git/#{@cookbook_name}")
		  `git checkout -b #{version}`
		  if !$?.exitstatus == 0
		     ui.error("Failed to checkout branch #{version} of #{@cookbook_name}")
		     exit 1
          end
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

      def set_cookbook_version(version)
          return  unless get_cookbook_version() != version
          contents = ''
          File.foreach("#{@github_tmp}/git/#{@cookbook_name}/metadata.rb") do |line|
              line.gsub!(/(version[\t\s]+)(.*)/i,"\\1 \"#{version}\"\n")
              contents = contents << line
          end
          File.open("#{@github_tmp}/git/#{@cookbook_name}/metadata.rb", 'w') {|f| f.write(contents) }
          return true
      end

    end
  end
end
