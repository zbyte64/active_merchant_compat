$:.push File.expand_path("../lib", __FILE__)
#require 'active_merchant/version'

Gem::Specification.new do |s|
  s.platform     = Gem::Platform::RUBY
  s.name         = 'activemerchantcompat'
  s.version      = '0.1'
  s.summary      = 'Framework and tools for dealing with credit card transactions.'
  s.description  = 'Active Merchant is a simple payment abstraction library used in and sponsored by Shopify. It is written by Tobias Luetke, Cody Fauser, and contributors. The aim of the project is to feel natural to Ruby users and to abstract as many parts as possible away from the user to offer a consistent interface across all supported gateways.'

  s.author = 'Tobias Luetke'
  s.email = 'tobi@leetsoft.com'
  s.homepage = 'http://activemerchant.org/'
  s.rubyforge_project = 'activemerchantcompat'

  s.files = Dir['CHANGELOG', 'README.md', 'MIT-LICENSE', 'CONTRIBUTORS', 'gem-public_cert.pem', 'lib/**/*', 'vendor/**/*']
  s.require_path = 'lib'

  s.has_rdoc = true if Gem::VERSION < '1.7.0'

  s.add_dependency('activemerchant')

  s.add_development_dependency('rake')
  #s.signing_key = ENV['GEM_PRIVATE_KEY']
  #s.cert_chain  = ['gem-public_cert.pem']
end