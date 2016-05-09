require 'eventmachine'
require './lib/utils/queue'
require './lib/utils/logger'


module Themis
    module Scheduler
        @logger = Themis::Utils::Logger::get

        def self.run
            contest_flow = Themis::Configuration::get_contest_flow
            EM.run do
                @logger.info "Scheduler started, CTRL+C to stop"

                tube_namespace = ENV['BEANSTALKD_TUBE_NAMESPACE']

                EM.add_periodic_timer contest_flow.push_period do
                    Themis::Utils::Queue::enqueue "#{tube_namespace}.main", 'push'
                end

                EM.add_periodic_timer contest_flow.poll_period do
                    Themis::Utils::Queue::enqueue "#{tube_namespace}.main", 'poll'
                end

                EM.add_periodic_timer contest_flow.update_period do
                    Themis::Utils::Queue::enqueue "#{tube_namespace}.main", 'update'
                end

                Signal.trap 'INT' do
                    EM.stop
                end

                Signal.trap 'TERM' do
                    EM.stop
                end
            end

            @logger.info 'Received shutdown signal'
        end
    end
end
