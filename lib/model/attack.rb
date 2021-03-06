require 'sequel'

module VolgaCTF
  module Final
    module Model
      class Attack < ::Sequel::Model
        many_to_one :team
        many_to_one :flag
      end
    end
  end
end
