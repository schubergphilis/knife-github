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

require 'knife-github/repo'
require 'knife-github/config'
require 'knife-github/version'
require 'knife-github/connection'
require 'mixlib/versioning'

class Chef
  class Knife
    module GithubBase

      def self.included(includer)
        includer.class_eval do

          option :github_url,
                 :long => "--github_url URL",
                 :description => "URL of the github enterprise appliance"

          option :github_organizations,
                 :long => "--github_org ORG:ORG",
                 :description => "Lookup repositories in this colon-separated list of organizations",
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

          option :github_proxy,
                 :long => "--github_proxy",
                 :description => "Enable proxy configuration for github api"
 
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
            @github_proxy           = locate_config_value("github_proxy")
            @github_tmp             = locate_config_value("github_tmp") || '/var/tmp/gitdiff'
            @github_tmp             = "#{@github_tmp}#{Process.pid}"
          end

          def check_gem_version
            url   = 'http://rubygems.org/api/v1/gems/knife-github.json'
            proxy = locate_config_value("github_proxy") 
            if proxy.nil?
              result = `curl -L -s #{url}`
              Chef::Log.debug("removing proxy in glogal git config")
              shell_out!("git config --global --unset http.proxy")
              shell_out!("git config --global --unset https.proxy")
            else
              Chef::Log.debug("Putting proxy in glogal git config")
              shell_out!("git config --global http.proxy #{proxy}")
              shell_out!("git config --global https.proxy #{proxy}")
              result = `curl --proxy #{proxy} -L -s #{url}`
            end
            begin
              json = JSON.parse(result)
              webversion = Mixlib::Versioning.parse(json['version'])
              thisversion = Mixlib::Versioning.parse(::Knife::Github::VERSION)
              if webversion > thisversion
                ui.info "INFO: New version (#{webversion.to_s}) of knife-github is available!"
                ui.info "INFO: Turn off this message with --github_no_update or add knife[:github_no_update] = true to your configuration"
              end 
              Chef::Log.debug("gem_local_version    : " + thisversion.to_s)
              Chef::Log.debug("gem_repo_version     : " + webversion.to_s)
              Chef::Log.debug("gem_downloads        : " + json['version_downloads'].to_s)
              Chef::Log.debug("gem_total_downloads  : " + json['downloads'].to_s)
 
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
            central_config = "/etc/githubrc.rb"
            if File.exists?(central_config)
              begin
                Github::Config.from_file(central_config)
              rescue
                Chef::Log.error("Something is wrong within your central config file: #{central_config}")
                Chef::Log.error("You will need to fix or remove this file to continue!")
                exit 1
              end
            end
            config[key] || Chef::Config[:knife][key] || Github::Config[key]
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
              get_org_data(org).each { |repo|
                name = repo['name']
                repos["#{name}"] = repo.to_hash 
              } 
            end
            repos
          end

          def get_org_data(org)
            dns_name = get_dns_name(@github_url)
            file = ENV['HOME'] + "/.chef/.#{dns_name}_#{org.downcase}.cache"

            cache_repo_data  = get_cache_data(file)
            github_repo_data = get_github_repo_data(org)
      
            github_repoList = Github::RepoList.new
      
            github_repo_data.each do |repo|
              github_repoList.push(repo)
              cache_repo = cache_repo_data.find { |k| k['name'] == repo.name }
              if cache_repo
                # found cache repo, update tags if latest_update is not equal
                if repo.updated_at == cache_repo['updated_at']
                  github_repoList.last.tags_all = cache_repo['tags_all']
                  github_repoList.last.tags_last = cache_repo['tags_last']
                else
                  github_repoList.last.update_tags! 
                end
              else
                # cannot find cache repo data, updating tags
                github_repoList.last.update_tags!
              end
            end
            write_cache_data(file, github_repoList)
            get_cache_data(file)
          end
          
          def connection
            @connection ||= GithubClient::Connection.new()
          end

          def write_cache_data(file, json)
            File.open(file, 'w') { |f| f.write(json.to_pretty_json) }
          end
      
          def get_cache_data(file)
            if File.exists?(file)
              return JSON.parse(File.read(file))
            else
              return JSON.parse("{}")
            end
          end
      
          def get_github_repo_data(org)
            arr  = []
            page = 1
            url  = @github_url + "/api/" + @github_api_version + "/orgs/" + org + "/repos"
            while true
              params = {'response' => 'json', 'page' => page }
              result = connection.send_get_request(url, params)
              break if result.nil? || result.count < 1
              result.each { |key| arr << Github::Repo.new(key) }
              page = page + 1
            end
            return arr
          end
      
          def get_dns_name(url)
            url = url.downcase.gsub("http://","") if url.downcase.start_with?("http://")
            url = url.downcase.gsub("https://","") if url.downcase.start_with?("https://")
            url.downcase
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
              cookbook_path = get_cookbook_path(@cookbook_name)
              Dir.chdir(cookbook_path)
              Chef::Log.debug "Adding tag"
              output = `git tag -a "#{version}" -m "Added tag #{version}" 2>&1`
              if $?.exitstatus != 0
                 Chef::Log.error("Could not add tag for: #{@cookbook_name}")
                 FileUtils.remove_entry(@github_tmp)
                 exit 1
              end
          end

          def get_cookbook_path(cookbook_name)
            cookbook_path = config[:cookbook_path] || Chef::Config[:cookbook_path]
            if cookbook_path.nil? || cookbook_path.empty?
              Chef::Log.error("Please specify a cookbook path")
              exit 1
            end

            cookbook_path = [ cookbook_path ] if cookbook_path.is_a?(String)

            unless File.exists?(cookbook_path.first) && File.directory?(cookbook_path.first)
              Chef::Log.error("Cannot find the directory: #{cookbook_path.first}")
              exit 1
            end

            cookbook_path = File.join(cookbook_path.first,cookbook_name)
          end 

          # Get the version number in the git version of the cookbook
          # @param version [String] Version
          def get_cookbook_version()
              version = nil
              cookbook_path = get_cookbook_path(@cookbook_name)
              File.foreach("#{cookbook_path}/metadata.rb") do |line|
                  if line =~ /version.*['"](.*)['"]/i
                     version = $1
                     break
                  end
              end
              if version.nil?
                 Chef::Log.error("Cannot get the version for cookbook #{@cookbook_name}")
                 exit 1
              end
              version
          end
        end
      end
    end
  end
end
