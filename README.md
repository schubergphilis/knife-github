knife-github
============

Chef knife plugin to interact with the github enterprise appliance.

Configurations
==========

### Central Configuration.
When working on customer admin machines, it's recommended to used an central configuration file.
This file should be created in: /etc/githubrc.rb and can contain any attribute in the following structure:

    github_url			        "https://github.schubergphilis.com"
    github_link             	"ssh"
    github_organizations    	[ "TLA-Cookbooks", "SBP-Cookbooks" ]

Please note: these options are recommended for the central config file.

### Personal Configuration.
You can also configure attributes within your ~/.chef/knife.rb in the following structure:

    knife[:github_token]           = '28374928374928374923874923842'  
    knife[:github_api_version]     = 'v3'  
    knife[:github_ssl_verify_mode] = 'verify_none'

Please note: these settings will overwrite the central settings. 
In a perfect world, your personal configuration file only contains your token information.

Attributes
==========

###### github_url
This will be the URL to your (personal) github enterprise appliance.
Here you can also use the github.com address if you don't have an internal appliance.

###### github_organizations
Here you specify the organizations that you want to taget when searching for cookbooks.  
The first entry will have priority over the other entries.

###### github_link \<optional\>
You can specify the link type that you would like to use to download your cookbooks, default is <tt>ssh</tt>.   
Options are <tt>ssh</tt> <tt>git</tt> <tt>http</tt> <tt>https</tt> <tt>svn</tt> 

###### github_api_version \<optional\>
The current and default version of the api is <tt>v3</tt> but this will allow you to target older versions if needed.

###### github_ssl_verify_mode \<optional\>
The plugin is using the underlying knife http implementation, hence it will have the same options to handle ssl.  
Currently the options are: <tt>verify_peer</tt> <tt>verify_none</tt>   

###### github_token \<optional\>
Token information is required when creating and deleting github repositories.  
With the command <tt>knife github token create</tt> you are able to create token information.


Other
=====

Cache files will be created into the: ~/.chef directory.
We use cache files to offload the api calls and increase the performance for repetitive executions
Updated to any repo inside the organization will cause the cache files to update.  
But in case of any problems, the cache files can be safely deleted.

