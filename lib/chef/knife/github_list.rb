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

    class GithubList < Knife

      deps do
        require 'chef/knife/github_base'

        include Chef::Knife::GithubBase
      end
      
      banner "knife github list [COOKBOOK] (options)"
      category "github"

      option :fields,
             :long => "--fields 'NAME, NAME'",
             :description => "The fields to output, comma-separated"

      option :fieldlist,
             :long => "--fieldlist",
             :description => "The available fields to output/filter",
             :boolean => true

      option :noheader,
             :long => "--noheader",
             :description => "Removes header from output",
             :boolean => true

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

        # Get the github link
        git_link = get_github_link(@github_link)
    
        # Filter all repo information based on the tags that we can find
        if config[:fields] || config[:fieldlist]
          all_repos = get_all_repos
          config[:fields] = "name" if config[:fields].nil? || config[:fields].empty?
        else 
          all_repos = {}
          if config[:all]
            get_all_repos.each { |k,v|
              cookbook = k
              cookbooks[k].nil? || cookbooks[k]['versions'].nil? ? version = "" : version = cookbooks[k]['versions'][0]['version']
              gh_url = get_github_link(v)
              gh_tag  = v['latest_tag']
              all_repos[cookbook] = { 'name' => cookbook, 'latest_cb_tag' => version, 'git_url' => gh_url, 'latest_gh_tag' => gh_tag }
            } 
          else
            cookbooks.each { |k,v|
              cookbook = k
              version  = v['versions'][0]['version']
              get_all_repos[k].nil? || get_github_link(get_all_repos[k]).nil? ? gh_url = ui.color("ERROR: Cannot find cookbook!", :red) : gh_url = get_github_link(get_all_repos[k])
              get_all_repos[k].nil? || get_all_repos[k]['latest_tag'].nil? ? gh_tag = ui.color("ERROR: No tags!", :red) : gh_tag = get_all_repos[k]['latest_tag']
              all_repos[cookbook] = { 'name' => cookbook, 'latest_cb_tag' => version, 'git_url' => gh_url, 'latest_gh_tag' => gh_tag } 
            }
          end
        end

        # Filter only on the cookbook name if its given on the command line
        @cookbook_name = name_args.first unless name_args.empty?
        if @cookbook_name
          repos = all_repos.select { |k,v| v["name"] == @cookbook_name }
        else
          repos = all_repos 
        end

        # Displaying information based on the fields and repos
        if config[:fields]
          object_list = []
          config[:fields].split(',').each { |n| object_list << ui.color(("#{n}").strip, :bold) }
        else
          object_list = [
            ui.color('Cookbook', :bold),
            ui.color('Github', :bold)
          ]
        end

        columns = object_list.count
        object_list = [] if config[:noheader]

        repos.each do |k,r|
          if config[:fields]
             config[:fields].downcase.split(',').each { |n| object_list << ((r[("#{n}").strip]).to_s || 'n/a') }
          else
            object_list << (r['name'] || 'n/a')
            object_list << (r['git_url'] || 'n/a')
          end
        end

        puts ui.list(object_list, :uneven_columns_across, columns)
        list_object_fields(repos) if locate_config_value(:fieldlist)
      end

      def list_object_fields(object)
        exit 1 if object.nil? || object.empty?
        object_fields = [
          ui.color('Key', :bold),
          ui.color('Type', :bold),
          ui.color('Value', :bold)
        ]

        object.first.each do |n|
          if n.class == Hash
            n.keys.each do |k,v|
              object_fields << ui.color(k, :yellow, :bold)
              object_fields << n[k].class.to_s
              if n[k].kind_of?(Array)
                object_fields << '<Array>'
              elsif n[k].kind_of?(Hash)
                object_fields << '<Hash>'
              else
                object_fields << ("#{n[k]}").strip.to_s
              end
            end
          end
        end

        puts "\n"
        puts ui.list(object_fields, :uneven_columns_across, 3)
      end
 
      def get_all_repos(orgs)
        # Parse every org and merge all into one hash
        repos = {}
        orgs.each do |org|
          get_repos(org).each { |repo| name = repo['name'] ; repos["#{name}"] = repo } 
        end
        repos
      end

      def get_repos(org)
        dns_name  = get_dns_name(@github_url)
        file_cache = "#{ENV['HOME']}/.chef/.#{dns_name.downcase}_#{org.downcase}.cache" 
        if File.exists?(file_cache)
          Chef::Log.debug("#{org} cache is created: " + (Time.now - File.ctime(file_cache)).to_i.to_s  + " seconds ago.")
          if Time.now - File.ctime(file_cache) > @github_cache
            # update cache file
            create_cache_file(file_cache, org)
          end
        else
          create_cache_file(file_cache, org)
        end
        # use cache files
        JSON.parse(File.read(file_cache))
      end

      def create_cache_file(file_cache, org)
        Chef::Log.debug("Updating the cache file: #{file_cache}")
        result = get_repos_github(org)
        File.open(file_cache, 'w') { |file| file.write(JSON.pretty_generate(result)) }
      end


 
      def get_repos_github(org)
        # Get all repo's for the org from github
        arr  = []
        page = 1
        url  = @github_url + "/api/" + @github_api_version + "/orgs/" + org + "/repos" 
        while true
          params = { 'page' => page }
          result = send_request(url, params)
          break if result.nil? || result.count < 1
          result.each { |key|
            if key['tags_url']
              tags = get_tags(key)
              key['tags'] = tags unless tags.nil? || tags.empty?
              key['latest_tag'] = tags.first['name'] unless tags.nil? || tags.empty?
              arr << key
            else 
              arr << key 
            end
          }
          page = page + 1
        end
        arr
      end


      def get_tags(repo)
        tags = send_request(repo['tags_url'])
        tags
      end


      def get_dns_name(url)
        url = url.downcase.gsub("http://","") if url.downcase.start_with?("http://")
        url = url.downcase.gsub("https://","") if url.downcase.start_with?("https://")
        url
      end

    end
  end
end
