require 'mixlib/versioning'
require 'knife-github/connection'
 
module Github
  class Repo

    def initialize(repo)
    # Instance variables
      @id          = repo['id']
      @name        = repo['name']
      @description = repo['description']
      @full_name   = repo['full_name']
      @private     = repo['private']
      @homapage    = repo['homepage']
      @created_at  = repo['created_at']
      @updated_at  = repo['updated_at']
      @pushed_at   = repo['pushed_at']
      @html_url    = repo['html_url']
      @ssh_url     = repo['ssh_url']
      @git_url     = repo['git_url']
      @svn_url     = repo['svn_url']
      @clone_url   = repo['clone_url']
      @tags_url    = repo['tags_url']
      @tags_all    = repo['tags_all']
      @tags_last   = repo['tags_last']
    end
 
    attr_reader :name, :id, :updated_at 
    attr_writer :tags_all, :tags_last

    def last_tag?
      get_last_tag(@tags_all)
    end

    def to_s
      @name
    end
    
    def update_tags!
      if @tags_url
        @tags_all = get_tags(@tags_url)
        @tags_last = get_last_tag(@tags_all)
      end
      self
    end

    def to_hash
      { 
        'id'          => @id,
        'name'        => @name,
        'description' => @description,
        'full_name'   => @full_name,
        'private'     => @private,
        'homepage'    => @homepage,
        'created_at'  => @created_at,
        'updated_at'  => @updated_at,
        'pushed_at'   => @pushed_at,
        'html_url'    => @html_url,
        'ssh_url'     => @ssh_url,
        'git_url'     => @git_url,
        'svn_url'     => @svn_url,
        'clone_url'   => @clone_url,
        'tags_url'    => @tags_url,
        'tags_all'    => @tags_all,
        'tags_last'   => @tags_last 
      }
    end

    def get_repo_data(orgs)
      orgs.each do |org| 
        get_org_data(org)
      end
    end

    private

    def get_tags(url)
      tags = []
      result = connection.send_get_request(url)
      result.each { |tag| tags.push(tag['name']) if tag['name'] =~ /^(\d*)\.(\d*)\.(\d*)$/ }
      tags || nil
    end
 
    def get_last_tag(tags)
      return nil if tags.nil? || tags.empty?
      base, last = "0.0.0", nil
      tags.each do |tag|
        if Mixlib::Versioning.parse(tag) >= Mixlib::Versioning.parse(base)
          last = tag
          base = last
        end
      end
      last
    end

    def connection
      @connection ||= GithubClient::Connection.new()
    end
  end

  class RepoList
    def initialize
      # Instance variables
      @repos = Array.new
    end
 
    def push(aRepo)
      pos = self.find_index(aRepo.name)
      if pos
        @repos[pos] = aRepo
      else
        @repos.push(aRepo)
      end
      self
    end

    def shift
      @repos.shift
    end

    def pop
      @repos.pop
    end

    def count
      @repos.count
    end

    def delete(key)
      @repos.delete(self.find(key))
      self
    end

    def last
      @repos.last
    end

    def find(key)
      @repos.find { |aRepo| aRepo.name == key }
    end

    def find_index(key)
      @repos.find_index { |aRepo| aRepo.name == key }
    end

    def [](key)
      return @repos[key] if key.kind_of?(Integer)
      return @repos.find { |aRepo| aRepo.name == key }
      nil
    end

    def to_pretty_json
      json = []
      @repos.each do |repo|
        json << repo.to_hash
      end
      JSON.pretty_generate(json)
    end

  end
end

