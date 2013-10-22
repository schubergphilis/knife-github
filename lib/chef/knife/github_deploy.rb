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
        require 'chef/cookbook_loader'
        require 'chef/cookbook_uploader'
      end
      
      banner "knife github deploy COOKBOOK VERSION (options)"
      category "github"

      option :quick,
             :short => "-q",
             :long => "--quick",
             :description => "Use the current master, do not check versions or tags",
             :boolean => false

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

        inChef = true
        isFrozen = true
        begin
            isFrozen = rest.get_rest("cookbooks/#{@cookbook_name}/#{cookbook_version}").frozen_version?
        rescue
            ui.warn "#{@cookbook_name} is not yet in chef"
            inChef = false
        end
        if config[:quick] && isFrozen
            ui.fatal "Quick mode cannot be used to replace a frozen cookbook"
            exit 1
        elsif config[:quick]
            ui.info "Using quick mode"
        end

		get_clone(github_link, @cookbook_name)

        # Might be first upload so need to catch that cookbook does not exist!
        get_cookbook_chef_versions()

        ui.info "Cookbook is frozen" if isFrozen
        if ! config[:quick]
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

        # If we have gotten this far we can just upload the cookbook
        cookbook_upload()
        FileUtils.remove_entry(@github_tmp)

      end

      def up_version(version)
          changed = false
          while true do
                ui.info("Trying to deploy version #{version}")
                if @versions.include?(version)
                   ui.info("Version #{version} is already in chef")
                   ui.confirm("Shall I change the version (No to Cancel)")
                   version = choose_version(version)
                   changed = true
                else
                   break
                end
          end
          version
      end

      def choose_version(version)
          if version =~ /(\d+)\.(\d+)\.(\d+)/
              minor = $3.to_i + 1
              version = "#{$1}.#{$2}.#{minor}"
              Chef::Log.debug("New version is #{version}")
          else
             Chef::Log.error("Version is in a format I cannot auto auto-update")
             exit 1
          end
          version
      end

      def cookbook_upload() 
		  args = ['cookbook', 'upload',  @cookbook_name ]
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

      def set_cookbook_version(version)
          return  unless get_cookbook_version() != version
          contents = ''
          File.foreach("#{@github_tmp}/git/#{@cookbook_name}/metadata.rb") do |line|
              line.gsub!(/(version[\t\s]+)(.*)/i,"\\1 #{version}\n")
              contents = contents << line
          end
          File.open("#{@github_tmp}/git/#{@cookbook_name}/metadata.rb", 'w') {|f| f.write(contents) }
          return true
      end

    end
  end
end
