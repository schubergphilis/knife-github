#
# Author:: Ian Southam (<isoutham@schubergphilis.com>)
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

module KnifeGithubPin

    # Pin a specific cookbook version to an environment
    #
    # Not specifically a github function but, sits nicely in with
    # download, deploy and so on
    # In some respects does duplicate some functionality that can be found
    # in spork but, I want a single set of tools that would help people
    # to get quickly up to speed with using chef in an industrialised environment
    class GithubPin < Chef::Knife
      deps do
        require 'chef/knife/github_base'
        require 'chef/knife/core/object_loader'
        require "json"
        include Chef::Knife::GithubBase
      end

      banner "knife github pin COOKBOOK [version] [environment]"
      category "github"

      def run
        # The run method.  The entry point into the class

        # validate base options from base module.
        validate_base_options

        # Display information if debug mode is on.
        display_debug_info

        cookbook_version = nil
        @cookbook_name = name_args.first unless name_args.empty?
        @version = nil
        @env     = nil

        if @cookbook_name.nil?
           Chef::Log.error("You must specify a cookbook name to use this module")
           exit 1;
        end

        # Parameter 2 can be a version or an environment (if version is not given) or nothing
        arg1 = name_args[1] unless name_args[1].nil?
        arg2 = name_args[2] unless name_args[2].nil?

        if(!arg1.nil? && !arg2.nil?)
            # we have a version and an environment
            @version = arg1
            @env = arg2
        end
        if(!arg1.nil? && arg2.nil?)
            # we have a version or an environment
            if Mixlib::Versioning.parse(arg1).nil?
                @env = arg1
            end
        end
        # If we have no version go and get it from the cookbook in the user's cookbooks path
        if @version.nil?
            unless @version = get_cookbook_version()
                ui.error('Could not get the version of the cookbook');
                exit 1;
            end
        end

        @envs = list_environments()
        if @env.nil?
            ask_which_environment()
        end
        ui.confirm("Pin version #{@version} of cookbook #{@cookbook_name} in Environment #{@env}")
        if @envs[@env].cookbook_versions.has_key?(@cookbook_name)
            cval = @envs[@env].cookbook_versions[@cookbook_name]
            if cval == @version
                ui.error "#{@cookbook_name} is already pinned to version #{cval}. Nothibg to do!"
                exit 1
            end
        end
        @envs[@env].cookbook_versions[@cookbook_name] = @version
        ui.info "Set version to #{@version} for environment #{@env}"
        if ! File.directory? @github_tmp
             Dir.mkdir(@github_tmp)
             Chef::Log.debug("Creating temporary directory #{@github_tmp}")
        end
        File.open("#{@github_tmp}/#{@env}.json", 'w') {|f| f.write JSON.pretty_generate(@envs[@env]) }
        Chef::Log.debug( "Json written to #{@github_tmp}/#{@env}.json" )

        # Finally do the upload
		args = ['environment',  "from_file", "#{@github_tmp}/#{@env}.json" ]
        upload = Chef::Knife::EnvironmentFromFile.new(args)
        upload.run

      end

      def list_environments()
        response = Hash.new
        Chef::Search::Query.new.search(:environment) do |e|
              response[e.name] = e unless e.nil?
        end
        response.delete('_default') if response.has_key?('_default');
        response
      end

      def ask_which_environment
        question = "Which environment do you wish to pin?\n"
        valid_responses = {}
        @envs.keys.each_with_index do |e, index|
            valid_responses[(index + 1).to_s] = e
            question << "#{index + 1}. #{e}\n"
        end
        question += "\n"
        response = ask_question(question).strip
        unless @env = valid_responses[response]
           ui.error("'#{response}' is not a valid value.")
           exit(1)
        end
        @env
      end

  end
end
