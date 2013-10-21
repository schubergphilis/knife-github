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

# require 'chef/knife'

class Chef
  class Knife
    module GithubBase

      def self.included(includer)
        includer.class_eval do

          deps do
            require 'chef/mixin/shell_out'
            require 'mixlib/versioning'
          end

          option :github_url,
                 :long => "--github_url URL",
                 :description => "URL of the github enterprise appliance"

          option :github_organizations,
                 :long => "--github_org ORG:ORG",
                 :description => "Lookup chef cookbooks in this colon-separated list of organizations",
                 :proc => lambda { |o| o.split(":") }

          option :github_link,
                 :long => "--github_link TYPE",
                 :description => "Link type: ssh, http, git (dafault: ssh)"

          option :github_api_version,
                 :long => "--github_api_ver VERSION",
                 :description => "Version number of the API (default: v3)"

          option :github_ssl_verify_mode,
                 :long => "--github_ssl_verify_mode",
                 :description => "SSL verify mode: verify_peer, verify_none (default: verify_peer)",
                 :boolean => true

          option :github_tmp,
                 :long => "--github_tmp PATH",
                 :description => "A path where temporary files for the diff function will be made default: /tmp/gitdiff)"

          def validate_base_options
            unless locate_config_value('github_url')
              ui.error "Github URL not specified"
              exit 1
            end
            unless locate_config_value('github_organizations')
              ui.error "Github organization(s) not specified"
              exit 1
            end

            @github_url             = locate_config_value("github_url")
            @github_organizations   = locate_config_value("github_organizations")
            @github_link            = locate_config_value("github_link") || 'ssh'
            @github_api_version     = locate_config_value("github_api_version") || 'v3'
            @github_ssl_verify_mode = locate_config_value("github_ssl_verify_mode") || 'verify_peer'
            @github_tmp             = locate_config_value("github_tmp") || '/var/tmp/gitdiff'
            @github_tmp             = "#{@github_tmp}#{Process.pid}"
          end

          def display_debug_info
            Chef::Log.debug("github_url: " + @github_url.to_s)
            Chef::Log.debug("github_org: " + @github_organizations.to_s)
            Chef::Log.debug("github_api: " + @github_api_version.to_s)
            Chef::Log.debug("github_link: " + @github_link.to_s)
            Chef::Log.debug("github_ssl_mode: " + @github_ssl_verify_mode.to_s)
          end

          def locate_config_value(key)
            key = key.to_sym
            config[key] || Chef::Config[:knife][key]
          end

          def  get_repo_clone_link
            link = locate_config_value('github_link')
            repo_link = case link
              when 'ssh' then 'ssh_url'
              when 'http' then 'clone_url'
              when 'https' then 'clone_url'
              when 'svn' then 'svn_url'
              when 'html' then 'html_url'
              when 'git' then 'git_url'
              else 'ssh_url'
            end
            return repo_link
          end

          def get_github_link(object)
            link = locate_config_value('github_link')
            git_link = case link
              when 'ssh' then 'ssh_url'
              when 'http' then 'clone_url'
              when 'https' then 'clone_url'
              when 'svn' then 'svn_url'
              when 'html' then 'html_url'
              when 'git' then 'git_url'
              else 'ssh_url'
            end
            if object.nil? || object.empty?
              return git_link
            else
              return object[git_link]
            end
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
            file_cache = "#{ENV['HOME']}/.chef/.#{dns_name.downcase}_#{org.downcase}" 

            if File.exists?(file_cache + ".json")
              json =  JSON.parse(File.read(file_cache + ".json"))
              json_updated = Time.parse(json['updated_at'])
              Chef::Log.info("#{org} - cache created at : " + json_updated.to_s)
              repo_updated = get_org_updated_time(org)
              Chef::Log.info("#{org} - repos updated at : " + repo_updated.to_s)
        
	      unless json_updated >= repo_updated 
                # update cache file
                create_cache_file(file_cache + ".cache", org)
                create_cache_json(file_cache + ".json", org)
              end
            else
              create_cache_file(file_cache + ".cache", org)
              create_cache_json(file_cache + ".json", org)
            end
            
            # use cache files
            JSON.parse(File.read(file_cache + ".cache"))
          end

          def create_cache_json(file, org)
            Chef::Log.debug("Updating the cache file: #{file}")
            url  = @github_url + "/api/" + @github_api_version + "/orgs/" + org
            result = send_request(url)
            File.open(file, 'w') { |f| f.write(JSON.pretty_generate(result)) }
          end

          def create_cache_file(file, org)
            Chef::Log.debug("Updating the cache file: #{file}")
            result = get_repos_github(org)
            File.open(file, 'w') { |f| f.write(JSON.pretty_generate(result)) }
          end
         
          def get_org_updated_time(org)
            url  = @github_url + "/api/" + @github_api_version + "/orgs/" + org
            result = send_request(url)
            Time.parse(result['updated_at'])
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
                  key['latest_tag'] = get_latest_tag(tags)
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

          def get_latest_tag(tags)
            return "" if tags.nil? || tags.empty?
            tags_arr =[]
            tags.each do |tag|
              tags_arr.push(Mixlib::Versioning.parse(tag['name'])) if tag['name'] =~ /^(\d*)\.(\d*)\.(\d*)$/
            end
            return "" if tags_arr.nil? || tags_arr.empty?
            return tags_arr.sort.last.to_s
          end

          def get_dns_name(url)
            url = url.downcase.gsub("http://","") if url.downcase.start_with?("http://")
            url = url.downcase.gsub("https://","") if url.downcase.start_with?("https://")
            url
          end

          def send_request(url, params = {})
            params['response'] = 'json'

            params_arr = []
            params.sort.each { |elem|
              params_arr << elem[0].to_s + '=' + CGI.escape(elem[1].to_s).gsub('+', '%20').gsub(' ','%20')
            }
            data = params_arr.join('&')

            if url.nil? || url.empty?
              puts "Error: Please specify a valid Github URL."
              exit 1
            end

            if @github_ssl_verify_mode == "verify_none"
              config[:ssl_verify_mode] = :verify_none
            elsif @github_ssl_verify_mode == "verify_peer"
              config[:ssl_verify_mode] = :verify_peer
            end

            github_url = "#{url}?#{data}" 
            Chef::Log.debug("URL: " + github_url.to_s)

            uri = URI.parse(github_url)
            req_body = Net::HTTP::Get.new(uri.request_uri)
            request = Chef::REST::RESTRequest.new("GET", uri, req_body, headers={})
 
            response = request.call
          
            if !response.is_a?(Net::HTTPOK) then
              puts "Error #{response.code}: #{response.message}"
              puts JSON.pretty_generate(JSON.parse(response.body))
              puts "URL: #{url}"
              exit 1
            end
            json = JSON.parse(response.body)
          end

          def get_clone(url, cookbook)
              if ! File.directory? @github_tmp
                 Dir.mkdir("#{@github_tmp}")
              end
              Dir.mkdir("#{@github_tmp}/git")
              output = `git clone #{url} #{@github_tmp}/git/#{cookbook} 2>&1`
              if $?.exitstatus != 0
                 Chef::Log.error("Could not clone the repository for: #{cookbook}")
                 FileUtils.remove_entry(@github_tmp)
                 exit 1
              end
              return true
          end


        end
      end
    end
  end
end
