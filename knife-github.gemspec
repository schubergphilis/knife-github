# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "knife-github/version"

Gem::Specification.new do |s|
  s.name              = "knife-github"
  s.version           = Knife::Github::VERSION
  s.platform          = Gem::Platform::RUBY
  s.has_rdoc          = false
  s.extra_rdoc_files  = ["LICENSE" ]
  s.authors           = ["Sander Botman"]
  s.email             = ["sbotman@schubergphilis.com"]
  s.homepage          = "https://github.com/schubergphilis/knife-github"
  s.summary           = %q{Github interaction support for Chef's Knife Command}
  s.description       = s.summary
  s.files             = `git ls-files`.split("\n")
  s.test_files        = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables       = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths     = ["lib"]

  s.add_dependency "mixlib-versioning", ">= 1.0.0"
  # s.add_dependency "chef", "~> 11.0.0"
end
