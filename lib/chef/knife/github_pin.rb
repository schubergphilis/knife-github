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

class Chef
  class Knife

    # Pin a specific cookbook version to an environment
    # 
    # Not specifically a github function but, sits nicely in with
    # download, deploy and so on
    # In some respects does duplicate some functionality that can be found
    # in spork but, I want a single set of tools that would help people
    # to get quickly up to speed with using chef in an industrialised environment
    class GithubPin < Knife
      deps do
        require 'chef/knife/github_base'

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
 
        if @cookbook_name.empty?
           Chef::Log.error("You must specify a cookbook name to use this module")
        end

        # Parameter 2 can be a version or an environment (if version is not given) or nothing
        arg1 = name_args.[1] unless name_args[1].empty?
        arg2 = name_args.[2] unless name_args[2].empty?

        if(!arg1.nil? && !arg2.nil?)
            # we have a version and an environment
            puts "Two parameters given"
        end
        if(!arg1.nil? && arg2.nil?)
            # we have a version or an environment
            puts "One parameters given"
        end
        if(arg1.nil? && arg2.nil?)
            # we have nothing
            puts "No parameters given"
        end
        cb1 = Mixlib::Versioning.parse(cookbook_version)
      end

    end
  end
end
