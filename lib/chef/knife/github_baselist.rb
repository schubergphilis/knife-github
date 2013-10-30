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
    module GithubBaseList

      def self.included(includer)
        includer.class_eval do
    
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
      
          def display_info(data, columns, match = [])
            object_list = []
      
            if config[:fields]
              config[:fields].split(',').each { |n| object_list << ui.color(("#{n}").capitalize.strip, :bold) }
            else
              columns.each { |c| r = c.split(","); object_list << ui.color(("#{r.last}").strip, :bold) }
            end
      
            col = object_list.count
            object_list = [] if config[:noheader]
      
            data.each do |k,v|
              if config[:fields]
                 config[:fields].downcase.split(',').each { |n| object_list << ((v["#{n}".strip]).to_s || 'n/a') }
              else
                color = :white
                if !match.empty? && !config[:all]
                  matches = []; match.each { |m| matches << v[m].to_s }
                  if matches.uniq.count == 1
                    next if config[:mismatch]
                  else
                    color = :yellow 
                  end
                end
                columns.each { |c|  r = c.split(","); object_list << ui.color((v["#{r.first}"]).to_s, color) || 'n/a' }
              end
            end
      
            puts ui.list(object_list, :uneven_columns_across, col)
            display_object_fields(data) if locate_config_value(:fieldlist)
          end
      
          def display_object_fields(object)
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
        end
      end
    end
  end
end
