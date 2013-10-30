require 'chef/knife'

class Chef
  class Knife
    # Implements the knife github deploy function
    # @author:: Ian Southam (<isoutham@schubergphilis.com>)
    # Copyright:: Copyright (c) 2013 Ian Southam.
    # This code is specific to our company workflow
    #
    # == Overview
    # All modes presume you have used github download to download a cookbook or
    # are creating a new cookbook
    #
    # === Examples
    # Deploy a development version of cookbook to your chef server
    #    knife github deploy cookbook_name 
    #    
    # Deploy a release version of cookbook to your chef server
    #    knife github deploy cookbook_name -f
    #
    # === Options
    # -f Operate in final release mode
    # -p Update the patch component of the version
    # -m Update the minor component of the version
    # -M Update the minor component of the version
    # 
    # == Operation Modes
    # Development (default)
    #
    # This will take a cookbook name
    # Do some basic version checks (if the current cookbook is frozen) and
    # upload it
    #
    # If the cookbook is frozen it will force you to choose a new version
    # and update the metadata accordingly
    #
    # Release (-f)
    #
    # You will be forced to select a new version.
    # You can choose via the options whether to increment the Major/minor or patch
    # revision numbers
    # The version will be tagged
    # Uploaded to the Chef server and frozen
    #
    # == Version numbers
    #
    # You can choose a specific version number by specifying it on the command
    # line.
    #
    # If you do not specify a version, the version will be the version in your
    # cookbook's metadata
    #
    # A warning is issued if the version is lower than the version in github
    #
    class GithubDeploy < Knife
      deps do
        require 'chef/knife/github_base'
        include Chef::Knife::GithubBase
        require 'chef/cookbook_loader'
        require 'chef/cookbook_uploader'
      end
      
      banner "knife github deploy COOKBOOK [VERSION] (options)"
      category "github"

      option :final,
             :short => "-f",
             :long => "--final",
             :description => "Bump version, make git tag and freeze",
             :boolean => true,
             :default => false

      option :major,
             :short => "-M",
             :long => "--major",
             :description => "In final mode, increase the major version ie. X.x.x",
             :boolean => true,
             :default => false

      option :minor,
             :short => "-m",
             :long => "--minor",
             :description => "In final mode, increase the minor version ie. x.X.x",
             :boolean => true,
             :default => false

      option :patch,
             :short => "-p",
             :long => "--patch",
             :description => "In final mode, increase the minor version ie. x.x.X (Default)",
             :boolean => true,
             :default => true

      def run
        # Main run entry point for the class

        validate_base_options      

        display_debug_info

        # Gather all repo information from github.
        get_all_repos = get_all_repos(@github_organizations.reverse)

        # Get all chef cookbooks and versions (hopefully chef does the error handeling).
        cookbooks = rest.get_rest("/cookbooks?num_version=1")

        @versions = []
        cookbook_version = nil
        @cookbook_name = name_args.first unless name_args.empty?
        cookbook_version = name_args[1] unless name_args[1].nil?

        if @cookbook_name
          repo = get_all_repos.select { |k,v| v["name"] == @cookbook_name }
        else
          Chef::Log.error("Cookbook not in git.  You must add it to git to use deploy")
          exit 1
        end

        if repo.empty?
          Chef::Log.error("Cookbook not in git.  You must add it to git to use deploy")
          exit 1
        end

        # is the cookbook in the cookbook_path?
        if cookbook_path_valid?(@cookbook_name, false).nil?
          Chef::Log.error("Cookbook is not in cookbook path")
          ui.info("HINT:  knife github clone #{@cookbook_name}")
          exit 1
        end

        # ----------------------------- #
        # The version can come
        # 1.  From the command line
        # 2.  From the cookbook
        # ----------------------------- #
        if cookbook_version.nil?
           cookbook_version = get_cookbook_version()
        end
        # Next check to see if the version in git is way ahead
        if ! get_all_repos[@cookbook_name]['latest_tag'].nil?
            cb1 = Mixlib::Versioning.parse(cookbook_version)
            cb2 = Mixlib::Versioning.parse(get_all_repos[@cookbook_name]['latest_tag'])
            if(cb2 > cb1)
                ui.confirm "Version in github #{cb2} is greater than the version you want to deploy #{cb1} - Continue"
            end
        end

        inChef = true
        isFrozen = false
        if (config[:major] || config[:minor])
            config[:patch] = false
        end
        if (config[:major] && config[:minor])
            config[:minor] = false
        end

        begin
            isFrozen = rest.get_rest("cookbooks/#{@cookbook_name}/#{cookbook_version}").frozen_version?
        rescue
            ui.warn "#{@cookbook_name} is not yet in chef"
            inChef = false
        end

        
        if config[:final]
            ui.info "Using Final mode"

        else
            ui.info "Using Development mode"
        end
        ui.info "Cookbook is frozen" if isFrozen

        # Might be first upload so need to catch that cookbook does not exist!
        get_cookbook_chef_versions()  unless ! inChef

        if config[:final]
            cookbook_version = up_version(cookbook_version)

            if repo[@cookbook_name]['tags'].select { |k| k['name'] == cookbook_version }.empty?
                ui.info("Cookbook #{cookbook_version} has no tag in Git")
                ui.confirm("Shall I add a tag for you?")
                set_cookbook_version(cookbook_version)
                add_tag(cookbook_version)
            else
                ui.confirm("Tag #{cookbook_version} exists - did you make this for this release?")
                checkout_tag(cookbook_version)
                set_cookbook_version(cookbook_version)
            end

            do_commit(cookbook_version, true)
        end

        # In Dev mode the version of the cookbook does not need to change
        # If however the cookbook is frozen, then the version has to change
        if ! config[:final] && isFrozen
            cookbook_version = up_version(cookbook_version)
            set_cookbook_version(cookbook_version)
            do_commit(cookbook_version, false)
        end

        # If we have gotten this far we can just upload the cookbook
        cookbook_upload()

      end

      # Ask user to increment current/desired version number
      # Method will exit if the user chooses not to increment the version
      #
      # @param version [String] Version
      # @return [String] New version number
      #
      def up_version(version)
          while true do
                ui.info("Trying to deploy version #{version}")
                if @versions.include?(version)
                   ui.info("Version #{version} is already in chef")
                   vt = choose_version(version)
                   ui.confirm("Shall I bump the version to #{vt} (No to Cancel)")
                   version = choose_version(version)
                else
                   break
                end
          end
          version
      end

      # Increment the current version according to the config
      # options config[major] config[minor] config[patch]
      # Method will exit if the user chooses not to increment the version
      #
      # @param version [String] Version
      # @return [String] New version number
      #
      def choose_version(version)
          if version =~ /(\d+)\.(\d+)\.(\d+)/
             major = $1
             minor = $2
             patch = $3
             major = major.to_i + 1 if config[:major]
             minor = minor.to_i + 1 if config[:minor]
             patch = patch.to_i + 1 if config[:patch]
             version = "#{major}.#{minor}.#{patch}"
             Chef::Log.debug("New version is #{version}")
          else
             Chef::Log.error("Version is in a format I cannot auto auto-update")
             exit 1
          end
          version
      end

      # Upload the cookbook to chef server
      # If mode is final, freeze the cookbook
      def cookbook_upload() 
          # Git meuk should not be uploaded use chefignore file instead
          # FileUtils.remove_entry("#{@github_tmp}/git/#{@cookbook_name}/.git")
		  args = ['cookbook', 'upload',  @cookbook_name ]
          if config[:final]
              args.push "--freeze"
          end
          upload = Chef::Knife::CookbookUpload.new(args)
          #upload.config[:cookbook_path] = "#{@github_tmp}/git"
          # plugin will throw its own errors
          upload.run
      end

      # If a tag is available in github check it out
      # Potentially quite dangerous as it could cause code to
      # get rolled back
      # @param version [String] Version
      def checkout_tag(version)
          ui.info "Checking out tag #{version}"
          cpath = get_cookbook_path(@cookbook_name)
          Dir.chdir(cpath);
		  `git checkout -b #{version}`
		  if !$?.exitstatus == 0
		     ui.error("Failed to checkout branch #{version} of #{@cookbook_name}")
		     exit 1
          end
      end

      # Get a sorted array of version for the cookbook
      def get_cookbook_chef_versions ()
          cookbooks = rest.get_rest("/cookbooks/#{@cookbook_name}?num_version=all")
          cookbooks[@cookbook_name]['versions'].each do |v|
              @versions.push v['version']
          end
      end

      # Get the version number in the git version of the cookbook
      # @param version [String] Version
      def get_cookbook_version()
          version = nil
          cpath = get_cookbook_path(@cookbook_name)
          File.foreach("#{cpath}/metadata.rb") do |line|
              if line =~ /version.*"(.*)"/i
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

      # Determine if the current cookbook path is valid and that there
      # is a cookbook of the correct name in there
      # @param cookbook [String] cookbook name
      # @return [String] Path to cookbook
      def get_cookbook_path(cookbook) 
          return cookbook_path_valid?(cookbook, false)
      end

      # Commit changes in git
      # @param version [String] cookbook version
      # @param push [Bool] true is the cookbook should also be pushed
      def do_commit(version, push)
          cpath = get_cookbook_path(@cookbook_name)
          Dir.chdir("#{cpath}")
          puts cpath
          output = `git commit -a -m "Deploy #{version}" 2>&1`
          if $?.exitstatus != 0
             if output !~ /nothing to commit/
                Chef::Log.error("Could not commit #{@cookbook_name}")
                puts output
                exit 1
             end
          end
          if push
              output = `git push --tags 2>&1`
              if $?.exitstatus != 0
                 Chef::Log.error("Could not push tag for: #{@cookbook_name}")
                 exit 1
              end
              output = `git push 2>&1`
          end
      end


      # Set the version in metadata.rb
      # @param version [String] cookbook version
      def set_cookbook_version(version)
          return  unless get_cookbook_version() != version
          contents = ''
          cpath = get_cookbook_path(@cookbook_name)
          File.foreach("#{cpath}/metadata.rb") do |line|
              line.gsub!(/(version[\t\s]+)(.*)/i,"\\1 \"#{version}\"\n")
              contents = contents << line
          end
          File.open("#{cpath}/metadata.rb", 'w') {|f| f.write(contents) }
          return true
      end

    end
  end
end
