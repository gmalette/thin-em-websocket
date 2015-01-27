# -*- encoding: utf-8 -*-
require File.expand_path('../lib/thin-em-websocket/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Sam Saffron"]
  gem.email         = ["sam.saffron@gmail.com"]
  gem.description   = %q{thin support for em-websocket}
  gem.summary       = %q{thin support for em-websocket}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "thin-em-websocket-gmalette"
  gem.require_paths = ["lib"]
  gem.version       = ThinEM::Websocket::VERSION
  gem.add_dependency('em-websocket', '>= 0.3.8')
  gem.add_dependency('thin', '>= 1.4.1')
end
