module VolgaCTF
  module Final
    module Domain
      def self.service(name, &block)
        service_dsl = ServiceDSL.new name
        service_dsl.instance_eval &block
        @_services << service_dsl.service
      end

      def self.get_services
        @_services
      end

      class Service
        attr_accessor :alias, :name, :vulnbox_endpoint_code,
                      :checker_endpoint, :attack_priority,
                      :poll_grace_period, :enable_in, :disable_in

        def initialize(service_alias)
          @alias = service_alias
          @name = nil
          @vulnbox_endpoint_code = nil
          @checker_endpoint = nil
          @attack_priority = false
          @poll_grace_period = 0
        end
      end

      class ServiceDSL
        attr_reader :service

        def initialize(service_alias)
          @service = Service.new(service_alias)
        end

        def name(name)
          @service.name = name
        end

        def vulnbox_endpoint_code(vulnbox_endpoint_code)
          @service.vulnbox_endpoint_code = vulnbox_endpoint_code
        end

        def checker_endpoint(checker_endpoint)
          @service.checker_endpoint = checker_endpoint
        end

        def attack_priority(attack_priority)
          @service.attack_priority = attack_priority
        end

        def poll_grace_period(poll_grace_period)
          @service.poll_grace_period = poll_grace_period
        end
      end

      protected
      @_services = []
    end
  end
end
