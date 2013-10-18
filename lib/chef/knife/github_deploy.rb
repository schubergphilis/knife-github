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
      
      banner "knife github deploy COOKBOOK [version] (options)"
      category "github"

      def run

        # validate base options from base module.
        validate_base_options      

        # Display information if debug mode is on.
        display_debug_info

      end


    end
  end
end
