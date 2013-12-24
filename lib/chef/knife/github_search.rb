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

module KnifeGithubSearch
  class GithubSearch < Chef::Knife

    deps do
      require 'chef/knife/github_base'
      include Chef::Knife::GithubBase
    end
      
    banner "knife github search STRING (options)"
    category "github"

    option :link,
           :short => "-l",
           :long => "--link",
           :description => "Show the links instead of the description",
           :boolean => true


    def run

      # validate base options from base module.
      validate_base_options      

      # Display information if debug mode is on.
      display_debug_info

      # Get the name_args from the command line
      query = name_args.join(' ')

      if query.nil? || query.empty? 
        Chef::Log.error("Please specify a search query")
        exit 1
      end 

      result = github_search_repos(query)

      if config[:link]
        columns = [ 'score,Score', 'name,Name', "url,URL" ]
      else
        columns = [ 'score,Score', 'name,Name', 'description,Description' ]
      end

      if result['repositories'].nil? || result['repositories'].empty?
        Chef::Log.error("No results when searching for: " + query)
      else
        items = []
        result['repositories'].each { |n| items << [ "#{n['name']}", n ] } 
        display_info(items, columns )
      end
    end

    def github_search_repos(query, params ={})
      # once the new search function is available, we can use these params
      params['q'] = query
      params['sort'] = 'stars'
      params['order'] = 'desc'
      params['response'] = 'json'

      url  = @github_url + "/api/" + @github_api_version + "/legacy/repos/search/" + query
      Chef::Log.debug("URL: #{url}")
      connection.send_get_request(url, params = {}) 
    end

  end
end
