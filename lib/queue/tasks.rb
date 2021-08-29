require 'sidekiq'
require 'mini_magick'

require './lib/model/bootstrap'
require './lib/util/logger'
require './lib/controller/competition_stage'
require './lib/controller/competition'
require './lib/controller/image'
require './lib/util/logger'

logger = ::VolgaCTF::Final::Util::Logger.get

config_redis = {
  url: "redis://#{::ENV['REDIS_HOST']}:#{::ENV['REDIS_PORT']}/#{::ENV['VOLGACTF_FINAL_QUEUE_REDIS_DB']}"
}

unless ::ENV.fetch('REDIS_PASSWORD', '').empty?
  config_redis[:password] = ::ENV['REDIS_PASSWORD']
end

::MiniMagick.configure do |config|
  config.cli = :graphicsmagick
end

::Sidekiq.default_worker_options = { 'retry' => 0 }

::Sidekiq.configure_server do |config|
  config.redis = config_redis

  config.on(:startup) do
    logger.info "Starting queue process, instance #{::ENV['QUEUE_INSTANCE']}"
    ::VolgaCTF::Final::Model.init
  end
  config.on(:quiet) do
    logger.info 'Got USR1, stopping further job processing...'
  end
  config.on(:shutdown) do
    logger.info 'Got TERM, shutting down process...'
  end
end

::Sidekiq.configure_client do |config|
  config.redis = config_redis
end

module VolgaCTF
  module Final
    module Queue
      module Tasks
        class Planner
          include ::Sidekiq::Worker
          sidekiq_options :retry => false

          def perform
            competition_ctrl = ::VolgaCTF::Final::Controller::Competition.new
            if competition_ctrl.can_trigger_round?
              ::VolgaCTF::Final::Queue::Tasks::TriggerRound.perform_async
            end

            if competition_ctrl.can_poll?
              ::VolgaCTF::Final::Queue::Tasks::TriggerPoll.perform_async
            end

            if competition_ctrl.can_recalculate?
              ::VolgaCTF::Final::Queue::Tasks::TriggerRecalculate.perform_async
            end

            if competition_ctrl.can_pause?
              ::VolgaCTF::Final::Queue::Tasks::TriggerPause.perform_async
            end

            if competition_ctrl.can_finish?
              ::VolgaCTF::Final::Queue::Tasks::TriggerFinish.perform_async
            end
          end
        end

        class TriggerRound
          include ::Sidekiq::Worker
          sidekiq_options :retry => false

          def perform
            competition_ctrl = ::VolgaCTF::Final::Controller::Competition.new
            competition_ctrl.trigger_round
          end
        end

        class TriggerPoll
          include ::Sidekiq::Worker
          sidekiq_options :retry => false

          def perform
            competition_ctrl = ::VolgaCTF::Final::Controller::Competition.new
            competition_ctrl.trigger_poll
          end
        end

        class TriggerRecalculate
          include ::Sidekiq::Worker
          sidekiq_options :retry => false

          def perform
            competition_ctrl = ::VolgaCTF::Final::Controller::Competition.new
            competition_ctrl.trigger_recalculate
          end
        end

        class TriggerPause
          include ::Sidekiq::Worker
          sidekiq_options :retry => false

          def perform
            competition_ctrl = ::VolgaCTF::Final::Controller::Competition.new
            competition_ctrl.pause
          end
        end

        class TriggerFinish
          include ::Sidekiq::Worker
          sidekiq_options :retry => false

          def perform
            competition_ctrl = ::VolgaCTF::Final::Controller::Competition.new
            competition_ctrl.finish
          end
        end

        class PullFlag
          include ::Sidekiq::Worker
          sidekiq_options :retry => false

          def perform(flag_str)
            flag = ::VolgaCTF::Final::Model::Flag.first(flag: flag_str)
            unless flag.nil?
              competition_ctrl = ::VolgaCTF::Final::Controller::Competition.new
              competition_ctrl.pull_flag(flag)
            end
          end
        end

        class ResizeImage
          include ::Sidekiq::Worker
          sidekiq_options :retry => false

          def perform(path, team_id)
            team = ::VolgaCTF::Final::Model::Team[team_id]
            return if team.nil?
            image_ctrl = ::VolgaCTF::Final::Controller::Image.new
            image_ctrl.resize(path, team)
          end
        end
      end
    end
  end
end
