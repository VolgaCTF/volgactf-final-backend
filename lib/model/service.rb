require 'sequel'

module VolgaCTF
  module Final
    module Model
      class Service < ::Sequel::Model
        plugin :optimistic_locking

        one_to_many :flags
        one_to_many :team_service_states
        one_to_many :team_service_history_states

        def serialize
          {
            id: id,
            name: name,
            attack_priority: attack_priority,
            award_defence_after: award_defence_after,
            enable_in: enable_in,
            disable_in: disable_in
          }
        end

        dataset_module do
          def enabled(round: nil)
            q = where(enabled: true)
            unless round.nil?
              q = q.where(disable_in: nil).or { disable_in >= round.id }
            end

            q.order(:id)
          end

          def enabling(round)
            where(enabled: false).exclude(enable_in: nil).where { enable_in <= round.id }
          end

          def disabling(round)
            where(enabled: true).exclude(disable_in: nil).where { disable_in <= round.id }
          end

          def named(service_alias)
            where(alias: service_alias).first
          end
        end
      end
    end
  end
end
