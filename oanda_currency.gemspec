Gem::Specification.new do |s|
  s.name        = 'oanda_currency'
  s.version     = '3.4.3'
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Emily Wilson']
  s.email       = ['emilywilson@privy.com']
  s.homepage    = 'https://github.com/Privy/Oanda_currency'
  s.summary     = 'Access the Oanda exchange rate data.'
  s.description = 'OandaCurrency extends Money::Bank::Base and gives you access
   to the current Oanda exchange rates.'
  s.license     = 'MIT'

  s.add_development_dependency 'ffi'
  s.add_development_dependency 'pry-byebug'
  s.add_development_dependency 'rspec', '>= 3.0.0'
  s.add_development_dependency 'yard', '>= 0.5.8'

  s.add_dependency 'faraday'
  s.add_dependency 'money', '6.13.1'

  s.files =  Dir.glob('{lib,spec}/**/*')
  s.files += %w[LICENSE README.md CHANGELOG.md AUTHORS]
  s.files += %w[Rakefile .gemtest Oanda_currency.gemspec]

  s.require_path = 'lib'
end
