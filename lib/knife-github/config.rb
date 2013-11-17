require 'mixlib/config'
module Github
    module Config
      extend Mixlib::Config
      config_strict_mode true
      config_context :knife do
        configurable :github_url
        configurable :github_organizations
      end
  end
end
