knife-github
============

Chef knife plugin to interact with the github enterprise appliance.

Attributes
==========

You can configure the following attributes within your knife.rb

    knife[:github_url]             = 'https://github.company.lan'  
    knife[:github_organizations]   = [ 'customer-cookbooks', 'central-cookbooks' ] 
    knife[:github_link]            = 'ssh' 
    knife[:github_api_version]     = 'v3'  
    knife[:github_cache]           = 900  
    knife[:github_ssl_verify_mode] = 'verify_none'

###### github_url
This will be the URL to your local github appliance.  
Here you can also use the github.com address if you don't have an internal appliance.

###### github_organizations
Here you specify the organizations that you want to taget when searching for cookbooks.  
The first entry will have priority over the other entries.

###### github_link \<optional\>
You can specify the link type that you would like to use to download your cookbooks, default is <tt>ssh</tt>.   
Options are <tt>ssh</tt> <tt>git</tt> <tt>http</tt> <tt>https</tt> <tt>svn</tt> 

###### github_api_version \<optional\>
The current and default version of the api is <tt>v3</tt> but this will allow you to target older versions if needed.

###### github_cache \<optional\>
This will be the lifetime of the cache files in seconds, default <tt>900</tt>. Cache files will be created into the: ~/.chef directory.  
We use cache files to offload the api calls and increase the performance for additional executions.

###### github_ssl_verify_mode \<optional\>
The plugin is using the underlying knife http implementation, hence it will have the same options to handle ssl.  
Currently the options are: <tt>verify_peer</tt> <tt>verify_none</tt> 

