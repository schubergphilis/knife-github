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
require "knife-github/version"

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

          option :github_no_update,
                 :long => "--github_no_update",
                 :description => "Turn github update checking off",
                 :boolean => true
 
          def validate_base_options
            unless locate_config_value('github_url')
              ui.error "Github URL not specified"
              exit 1
            end
            unless locate_config_value('github_organizations')
              ui.error "Github organization(s) not specified"
              exit 1
            end
            unless locate_config_value('github_no_update')
              check_gem_version
            end

            @github_url             = locate_config_value("github_url")
            @github_organizations   = locate_config_value("github_organizations")
            @github_link            = locate_config_value("github_link") || 'ssh'
            @github_api_version     = locate_config_value("github_api_version") || 'v3'
            @github_ssl_verify_mode = locate_config_value("github_ssl_verify_mode") || 'verify_peer'
            @github_tmp             = locate_config_value("github_tmp") || '/var/tmp/gitdiff'
            @github_tmp             = "#{@github_tmp}#{Process.pid}"
          end

          def check_gem_version
            url  = 'http://rubygems.org/api/v1/gems/knife-github.json'
            result = `curl -L -s #{url}`
            begin
              json = JSON.parse(result)
              webversion = Mixlib::Versioning.parse(json['version'])
              thisversion = Mixlib::Versioning.parse(::Knife::Github::VERSION)
              if webversion > thisversion
                ui.info "INFO: New version (#{webversion.to_s}) of knife-github is available!"
                ui.info "INFO: Turn off this message with --github_no_update or add knife[:github_no_update] = true to your configuration"
              end 
              Chef::Log.debug("local_gem_version    : " + thisversion.to_s)
              Chef::Log.debug("repo_gem_version     : " + webversion.to_s)
              Chef::Log.debug("repo_downloads       : " + json['version_downloads'].to_s)
              Chef::Log.debug("repo_total_downloads : " + json['downloads'].to_s)
 
            rescue
              ui.info "INFO: Cannot verify gem version information from rubygems.org"
              ui.info "INFO: Turn off this message with --github_no_update or add knife[:github_no_update] = true to your configuration"
            end
          end

          def display_debug_info
            Chef::Log.debug("github_url           : " + @github_url.to_s)
            Chef::Log.debug("github_org           : " + @github_organizations.to_s)
            Chef::Log.debug("github_api           : " + @github_api_version.to_s)
            Chef::Log.debug("github_link          : " + @github_link.to_s)
            Chef::Log.debug("github_ssl_mode      : " + @github_ssl_verify_mode.to_s)
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
            params = {'response' => 'json'} 
            result = send_request(url, params)
            File.open(file, 'w') { |f| f.write(JSON.pretty_generate(result)) }
          end

          def create_cache_file(file, org)
            Chef::Log.debug("Updating the cache file: #{file}")
            result = get_repos_github(org)
            File.open(file, 'w') { |f| f.write(JSON.pretty_generate(result)) }
          end
         
          def get_org_updated_time(org)
            url  = @github_url + "/api/" + @github_api_version + "/orgs/" + org
            params = {'response' => 'json'}
            result = send_request(url, params)
            Time.parse(result['updated_at'])
          end

          def get_repos_github(org)
            # Get all repo's for the org from github
            arr  = []
            page = 1
            url  = @github_url + "/api/" + @github_api_version + "/orgs/" + org + "/repos" 
            while true
              params = {'response' => 'json', 'page' => page }
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
            params = {'response' => 'json'}
            tags = send_request(repo['tags_url'], params)
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
            unless params.empty?
              params_arr = []
              params.sort.each { |elem|
                params_arr << elem[0].to_s + '=' + CGI.escape(elem[1].to_s).gsub('+', '%20').gsub(' ','%20')
              }
              data = params_arr.join('&')
              url = "#{url}?#{data}" 
            end

            if @github_ssl_verify_mode == "verify_none"
              config[:ssl_verify_mode] = :verify_none
            elsif @github_ssl_verify_mode == "verify_peer"
              config[:ssl_verify_mode] = :verify_peer
            end

            Chef::Log.debug("URL: " + url.to_s)

            uri = URI.parse(url)
            req_body = Net::HTTP::Get.new(uri.request_uri)
            request = Chef::REST::RESTRequest.new("GET", uri, req_body, headers={})
 
            response = request.call
          
            unless response.is_a?(Net::HTTPOK) then
              puts "Error #{response.code}: #{response.message}"
              puts JSON.pretty_generate(JSON.parse(response.body))
              puts "URL: #{url}"
              exit 1
            end

            begin
              json = JSON.parse(response.body)
            rescue
              ui.warn "The result on the RESTRequest is not in json format"
              ui.warn "Output: " + response.body
              exit 1
            end
            return json
          end

          def get_clone(url, cookbook)
              if ! File.directory? @github_tmp
                 Dir.mkdir("#{@github_tmp}")
              end
              Dir.mkdir("#{@github_tmp}/git")
              ui.info("Getting #{@cookbook_name} from #{url}")
              output = `git clone #{url} #{@github_tmp}/git/#{cookbook} 2>&1`
              if $?.exitstatus != 0
                 Chef::Log.error("Could not clone the repository for: #{cookbook}")
                 FileUtils.remove_entry(@github_tmp)
                 exit 1
              end
              return true
          end

          def add_tag(version)
              cpath = cookbook_path_valid?(@cookbook_name, false)
              Dir.chdir(cpath)
              Chef::Log.debug "Adding tag"
              output = `git tag -a "#{version}" -m "Added tag #{version}" 2>&1`
              if $?.exitstatus != 0
                 Chef::Log.error("Could not add tag for: #{@cookbook_name}")
                 FileUtils.remove_entry(@github_tmp)
                 exit 1
              end
          end

          def cookbook_path_valid?(cookbook_name, check_exists)
            cookbook_path = config[:cookbook_path] || Chef::Config[:cookbook_path]
            if cookbook_path.nil? || cookbook_path.empty?
              Chef::Log.error("Please specify a cookbook path")
              exit 1
            end

            unless File.exists?(cookbook_path.first) && File.directory?(cookbook_path.first)
              Chef::Log.error("Cannot find the directory: #{cookbook_path.first}")
              exit 1
            end

            cookbook_path = File.join(cookbook_path.first,cookbook_name)
            if check_exists
                if File.exists?(cookbook_path)
                  ui.info("Processing [S] #{cookbook_name}")
                  Chef::Log.info("Path to #{cookbook_path} already exists, skipping.")
                  return nil
                end
            else
                if ! File.exists?(cookbook_path)
                  return nil
                end
            end
            return cookbook_path
          end

        end
      end
    end
  end
end
