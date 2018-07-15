require 'omniauth-memberclicks-rest/version'
require 'omniauth/strategies/memberclicks_rest.rb'

module Omniauth
  module MemberclicksREST
    OmniAuth.config.add_camelization 'memberclicks_rest', 'MemberclicksREST'
  end
end
