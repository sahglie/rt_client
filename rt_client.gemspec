# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "rt-client/version"

Gem::Specification.new do |s|
  s.name        = "rt-client"
  s.version     = RTClient::VERSION
  s.authors     = ["Rob Vinson"]
  s.email       = ["rob.vinson@gmail.com"]
  s.homepage    = "https://github.com/robvinson/rt_client"
  s.summary     = %q{For accessing the REST interface of a Request Tracker instance.}
  s.description     = %q{RT_Client is a ruby object that accesses the REST interface version 1.0 of a Request Tracker instance.  See http://www.bestpractical.com/ for Request Tracker.  This is a fork of Tom Lahti's rt-client gem.}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  s.add_runtime_dependency "rest-client", '>= 0.9'
  s.add_runtime_dependency "mail", '~> 2.5.3'
  s.add_runtime_dependency "mime-types", '>= 1.16'
  s.add_runtime_dependency "archive-tar-minitar", '>= 0.5'
  s.add_runtime_dependency "nokogiri", '>= 1.2'
end
