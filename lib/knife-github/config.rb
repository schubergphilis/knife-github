require 'mixlib/config'
module Github
    module Config
      extend Mixlib::Config
      config_context :knife do
        configurable :github_url
        configurable :github_organizations
        configurable :github_link
        configurable :github_api_version
        configurable :github_ssl_verify_mode
        configurable :github_proxy
      end
  end
end
