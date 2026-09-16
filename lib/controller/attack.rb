require 'date'

require './lib/controller/round'
require './lib/controller/team_service_state'
require './lib/controller/scoreboard'
require './lib/util/event_emitter'
require './lib/const/submit_result'
require './lib/controller/domain'
require './lib/queue/tasks'

module VolgaCTF
  module Final
    module Controller
      class Attack
        def initialize
          @domain_ctrl = ::VolgaCTF::Final::Controller::Domain.new
          @team_service_state_ctrl = ::VolgaCTF::Final::Controller::TeamServiceState.new
          @round_ctrl = ::VolgaCTF::Final::Controller::Round.new
          @scoreboard_ctrl = ::VolgaCTF::Final::Controller::Scoreboard.new
        end

        def handle(stage, team, data)
          cutoff = ::DateTime.now
          attempt = ::VolgaCTF::Final::Model::AttackAttempt.create(
            occured_at: cutoff,
            request: data.to_s,
            response: ::VolgaCTF::Final::Const::SubmitResult::ERROR_UNKNOWN,
            team_id: team.id
          )

          unless data.respond_to?('match')
            r = ::VolgaCTF::Final::Const::SubmitResult::ERROR_FLAG_INVALID
            attempt.response = r
            attempt.save
            return r
          end

          match_ = data.match(/^[\da-f]{32}=$/)
          if match_.nil?
            r = ::VolgaCTF::Final::Const::SubmitResult::ERROR_FLAG_INVALID
            attempt.response = r
            attempt.save
            return r
          end

          flag = ::VolgaCTF::Final::Model::Flag.first_match(match_[0])

          if flag.nil?
            r = ::VolgaCTF::Final::Const::SubmitResult::ERROR_FLAG_NOT_FOUND
            attempt.response = r
            attempt.save
            return r
          end

          if flag.team_id == team.id
            r = ::VolgaCTF::Final::Const::SubmitResult::ERROR_FLAG_YOUR_OWN
            attempt.response = r
            attempt.save
            return r
          end

          unless @team_service_state_ctrl.up?(stage, team, flag.service)
            r = ::VolgaCTF::Final::Const::SubmitResult::ERROR_SERVICE_STATE_INVALID
            attempt.response = r
            attempt.save
            return r
          end

          if flag.expired_at < cutoff
            r = ::VolgaCTF::Final::Const::SubmitResult::ERROR_FLAG_EXPIRED
            attempt.response = r
            attempt.save
            return r
          end

          r = nil
          begin
            ::VolgaCTF::Final::Model::DB.transaction do
              ::VolgaCTF::Final::Model::Attack.create(
                occured_at: cutoff,
                processed: false,
                team_id: team.id,
                flag_id: flag.id
              )

              if flag.service.attack_priority && flag.service.award_defence_after.nil?
                award_defence_after = @round_ctrl.last_number

                ::VolgaCTF::Final::Model::DB.after_commit do
                  ::VolgaCTF::Final::Queue::Tasks::UpdateServiceAwardDefenceAfter.perform_async(team.id, flag.service.id, award_defence_after)
                end
              end

              r = ::VolgaCTF::Final::Const::SubmitResult::SUCCESS

              log_data = {
                actor_team_id: team.id,
                target_team_id: flag.team_id,
                target_service_id: flag.service_id
              }

              if @scoreboard_ctrl.broadcast?
                ::VolgaCTF::Final::Util::EventEmitter.broadcast_log(4, log_data)
              else
                ::VolgaCTF::Final::Util::EventEmitter.emit_log(4, log_data)
              end
            end
          rescue ::Sequel::UniqueConstraintViolation => e
            r = ::VolgaCTF::Final::Const::SubmitResult::ERROR_FLAG_SUBMITTED
          end

          attempt.response = r
          attempt.save
          return r
        end
      end
    end
  end
end
