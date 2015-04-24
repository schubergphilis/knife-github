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

module KnifeGithubList
  class GithubList < Chef::Knife

    deps do
      require 'chef/knife/github_base'
      include Chef::Knife::GithubBase
      require 'chef/knife/github_baselist'
      include Chef::Knife::GithubBaseList
    end

    banner "knife github list [COOKBOOK] (options)"
    category "github"

    option :all,
           :short => "-a",
           :long => "--all",
           :description => "Get all cookbooks from github.",
           :boolean => true

    def run
      # validate base options from base module.
      validate_base_options

      # Display information if debug mode is on.
      display_debug_info

      # Gather all repo information from github.
      get_all_repos = get_all_repos(@github_organizations.reverse)

      # Get all chef cookbooks and versions (hopefully chef does the error handeling).
      cookbooks = rest.get_rest("/cookbooks?num_version=1")

      #Get the github link
      git_link = get_repo_clone_link

      # Filter all repo information based on the tags that we can find
      if config[:fields] || config[:fieldlist]
        all_repos = get_all_repos
        config[:fields] = "name" if config[:fields].nil? || config[:fields].empty?
      else
        all_repos = {}
        if config[:all]
          get_all_repos.each { |k,v|
            cookbooks[k].nil? || cookbooks[k]['versions'].nil? ? version = "" : version = cookbooks[k]['versions'][0]['version']
            all_repos[k] = { 'name' => k, 'latest_cb_tag' => version, 'git_url' => v[git_link], 'latest_gh_tag' => v['latest_tag'] }
          }
        else
          cookbooks.each { |k,v|
            get_all_repos[k].nil? || get_all_repos[k][git_link].nil? ? gh_url = ui.color("ERROR: Cannot find cookbook!", :red) : gh_url = get_all_repos[k][git_link]
            get_all_repos[k].nil? || get_all_repos[k]['latest_tag'].nil? ? gh_tag = ui.color("ERROR: No tags!", :red) : gh_tag = get_all_repos[k]['latest_tag']
            all_repos[k] = { 'name' => k, 'latest_cb_tag' => v['versions'][0]['version'], 'git_url' => gh_url, 'latest_gh_tag' => gh_tag }
          }
        end
      end

      # Filter only on the cookbook name if its given on the command line
      @cookbook_name = name_args.first unless name_args.empty?
      if @cookbook_name
        repos = all_repos.select { |k,v| v["name"] == @cookbook_name }
      else
        repos = all_repos.sort_by { |k, v| v["name"] }
      end

      columns = [ 'name,Chef Store', 'git_url,Github Store' ]

      if repos.nil? || repos.empty?
        Chef::Log.error("No repositories found.")
      else
        display_info(repos, columns )
      end
    end
  end
end
