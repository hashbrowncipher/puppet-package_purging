ENV['STRICT_VARIABLES']='yes'
require 'puppetlabs_spec_helper/module_spec_helper'

RSpec.configure do |config|
    config.raise_errors_for_deprecations!
    config.mock_with :rspec do |mocks|
        mocks.verify_partial_doubles = true
    end
end
