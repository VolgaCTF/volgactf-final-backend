require 'eventmachine'

require './lib/util/logger'
require './lib/queue/tasks'

module VolgaCTF
  module Final
    class Scheduler
      def initialize
        @logger = ::VolgaCTF::Final::Util::Logger.get
      end

      def run
        ::EM.run do
          @logger.info('Scheduler started, CTRL+C to stop')

          ::EM.add_periodic_timer 5 do
            ::VolgaCTF::Final::Queue::Tasks::Planner.perform_async
          end

          ::EM.add_periodic_timer 30 do
            ::VolgaCTF::Final::Queue::Tasks::OpenDataIndexCleaner.perform_async
          end

          ::EM.add_periodic_timer 150 do
            ::VolgaCTF::Final::Queue::Tasks::UploadDirCleaner.perform_async
          end

          ::Signal.trap 'INT' do
            ::EM.stop
          end

          ::Signal.trap 'TERM' do
            ::EM.stop
          end
        end

        @logger.info('Received shutdown signal')
      end
    end
  end
end
