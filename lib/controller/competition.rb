require 'date'

require 'ip'
require 'volgactf/final/checker/result'

require './lib/controller/competition_stage'
require './lib/controller/round'
require './lib/controller/team'
require './lib/controller/service'
require './lib/controller/remote_checker'
require './lib/controller/team_service_state'
require './lib/controller/score'
require './lib/controller/scoreboard'
require './lib/controller/flag'
require './lib/controller/flag_poll'
require './lib/queue/tasks'
require './lib/const/flag_poll_state'
require './lib/util/logger'
require './lib/controller/domain'

module VolgaCTF
  module Final
    module Controller
      class Competition
        def initialize
          @logger = ::VolgaCTF::Final::Util::Logger.get
          @stage_ctrl = ::VolgaCTF::Final::Controller::CompetitionStage.new
          @round_ctrl = ::VolgaCTF::Final::Controller::Round.new
          @team_ctrl = ::VolgaCTF::Final::Controller::Team.new
          @service_ctrl = ::VolgaCTF::Final::Controller::Service.new
          @remote_checker_ctrl = ::VolgaCTF::Final::Controller::RemoteChecker.new
          @team_service_state_ctrl = ::VolgaCTF::Final::Controller::TeamServiceState.new
          @score_ctrl = ::VolgaCTF::Final::Controller::Score.new
          @flag_poll_ctrl = ::VolgaCTF::Final::Controller::FlagPoll.new
          @flag_ctrl = ::VolgaCTF::Final::Controller::Flag.new
          @scoreboard_ctrl = ::VolgaCTF::Final::Controller::Scoreboard.new
          @domain_ctrl = ::VolgaCTF::Final::Controller::Domain.new
        end

        def init
          ::VolgaCTF::Final::Model::DB.transaction do
            @domain_ctrl.init
            @service_ctrl.enable_all
            @stage_ctrl.init
            @scoreboard_ctrl.enable_broadcast
          end
        end

        def enqueue_start
          @stage_ctrl.enqueue_start
        end

        def enqueue_pause
          @stage_ctrl.enqueue_pause
        end

        def enqueue_finish
          @stage_ctrl.enqueue_finish
        end

        def can_trigger_round?
          stage = @stage_ctrl.current
          if stage.starting?
            return true
          end

          cutoff = ::DateTime.now
          return stage.started? && @round_ctrl.gap_filled?(cutoff)
        end

        def trigger_round
          stage = @stage_ctrl.current
          if stage.starting?
            @stage_ctrl.start
          end

          round = @round_ctrl.create_round

          @service_ctrl.ensure_enable(round)

          @team_ctrl.all_teams(true).each do |team|
            @service_ctrl.enabled_services(shuffle: true, round: round).each do |service|
              begin
                push_flag(team, service, round)
              rescue => e
                @logger.error(e.to_s)
              end
            end
          end
        end

        def can_poll?
          stage = @stage_ctrl.current
          return false unless stage.any?(:started, :pausing, :finishing)

          cutoff = ::DateTime.now
          return @round_ctrl.can_poll?(cutoff)
        end

        def trigger_poll
          cutoff = ::DateTime.now
          flags = ::VolgaCTF::Final::Model::Flag.living(cutoff).all
          poll = @round_ctrl.create_poll

          @team_ctrl.all_teams(true).each do |team|
            @service_ctrl.enabled_services(shuffle: true).each do |service|
              flag = flags.select { |f| f.team_id == team.id && f.service_id == service.id }.sample

              unless flag.nil?
                begin
                  pull_flag(flag)
                rescue => e
                  @logger.error(e.to_s)
                end
              end
            end
          end
        end

        def can_recalculate?
          stage = @stage_ctrl.current
          stage.any?(:started, :pausing, :finishing) && !@round_ctrl.expired_rounds(::DateTime.now).empty?
        end

        def trigger_recalculate
          cutoff = ::DateTime.now
          positions_updated = false
          @round_ctrl.expired_rounds(cutoff).each do |round|
            updated = recalculate_round(round)
            break unless updated
            positions_updated = updated
          end

          if positions_updated
            @score_ctrl.update_total_scores
            @scoreboard_ctrl.update
          end
        end

        def can_pause?
          @stage_ctrl.current.pausing? && @round_ctrl.last_round_finished?
        end

        def pause
          @stage_ctrl.pause
        end

        def can_finish?
          @stage_ctrl.current.finishing? && @round_ctrl.last_round_finished?
        end

        def finish
          @stage_ctrl.finish
        end

        def handle_push(flag, status, label, message)
          return unless @domain_ctrl.available?

          ::VolgaCTF::Final::Model::DB.transaction(
            retry_on: [::Sequel::UniqueConstraintViolation],
            num_retries: nil
          ) do
            if status == ::VolgaCTF::Final::Checker::Result::UP
              cutoff = ::DateTime.now
              flag.pushed_at = cutoff
              expires = (cutoff.to_time + @domain_ctrl.settings.flag_lifetime).to_datetime
              flag.expired_at = expires
              flag.label = label
              flag.save

              ::VolgaCTF::Final::Model::DB.after_commit do
                @logger.info("Successfully pushed flag `#{flag.flag}`!")
                ::VolgaCTF::Final::Queue::Tasks::PullFlag.perform_async(flag.flag)
              end
            else
              @logger.info("Failed to push flag `#{flag.flag}` (status code "\
                           "#{status})!")
            end

            @team_service_state_ctrl.update_push_state(
              flag.team,
              flag.service,
              status,
              message
            )
          end
        end

        def handle_pull(poll, status, message)
          ::VolgaCTF::Final::Model::DB.transaction(
            retry_on: [::Sequel::UniqueConstraintViolation],
            num_retries: nil
          ) do
            if status == ::VolgaCTF::Final::Checker::Result::UP
              poll.state = ::VolgaCTF::Final::Const::FlagPollState::SUCCESS
            else
              poll.state = ::VolgaCTF::Final::Const::FlagPollState::ERROR
            end

            poll.updated_at = ::DateTime.now
            poll.save

            flag = poll.flag
            @team_service_state_ctrl.update_pull_state(
              flag.team,
              flag.service,
              status,
              message
            )

            if status == ::VolgaCTF::Final::Checker::Result::UP
              @logger.info("Successfully pulled flag `#{flag.flag}`!")
            else
              @logger.info("Failed to pull flag `#{flag.flag}` (status code "\
                           "#{status})!")
            end
          end
        end

        def team_service_endpoint(team, service)
          ::IP.new(eval(service.vulnbox_endpoint_code % { team_network: team.network }))
        end

        def pull_flag(flag)
          team = flag.team
          service = flag.service
          round = flag.round
          flag_poll = nil

          ::VolgaCTF::Final::Model::DB.transaction do
            flag_poll = @flag_poll_ctrl.create_flag_poll(flag)

            ::VolgaCTF::Final::Model::DB.after_commit do
              @logger.info("Pulling flag `#{flag.flag}` from service "\
                           "`#{service.name}` of `#{team.name}` ...")
              job_data = {
                params: {
                  request_id: flag_poll.id,
                  endpoint: team_service_endpoint(team, service).to_s,
                  capsule: flag.capsule,
                  label: flag.label
                },
                metadata: {
                  timestamp: ::DateTime.now.to_s,
                  round: round.id,
                  team_name: team.name,
                  service_name: service.name
                },
                report_url: "http://#{::ENV['VOLGACTF_FINAL_MASTER_HOST']}:#{::ENV['VOLGACTF_FINAL_MASTER_PORT']}/api/checker/v2/report_pull"
              }.to_json

              call_res = @remote_checker_ctrl.pull(service.checker_endpoint, job_data)
              @logger.info("REST API PULL call to #{service.checker_endpoint} returned HTTP #{call_res}")
            end
          end
        end

        private
        def push_flag(team, service, round)
          ::VolgaCTF::Final::Model::DB.transaction(
            retry_on: [::Sequel::UniqueConstraintViolation],
            num_retries: nil
          ) do
            flag = @flag_ctrl.issue(team, service, round)

            ::VolgaCTF::Final::Model::DB.after_commit do
              @logger.info("Pushing flag `#{flag.flag}` to service "\
                           "`#{service.name}` of `#{team.name}` ...")
              job_data = {
                params: {
                  endpoint: team_service_endpoint(team, service).to_s,
                  capsule: flag.capsule,
                  label: flag.label
                },
                metadata: {
                  timestamp: ::DateTime.now.to_s,
                  round: round.id,
                  team_name: team.name,
                  service_name: service.name
                },
                report_url: "http://#{::ENV['VOLGACTF_FINAL_MASTER_HOST']}:#{::ENV['VOLGACTF_FINAL_MASTER_PORT']}/api/checker/v2/report_push"
              }.to_json

              call_res = @remote_checker_ctrl.push(service.checker_endpoint, job_data)
              @logger.info("REST API PUSH call to #{service.checker_endpoint} returned HTTP #{call_res}")
            end
          end
        end

        def recalculate_round(round)
          ::VolgaCTF::Final::Model::DB.transaction do
            @score_ctrl.init_scores(round)
            rel_flags = ::VolgaCTF::Final::Model::Flag.relevant(round)
            err_update = false
            rel_flags.each do |flag|
              begin
                @score_ctrl.update_score(flag)
              rescue => e
                @logger.error(e.to_s)
                err_update = true
              end

              break if err_update
            end

            return false if err_update

            round.finished_at = ::DateTime.now
            round.save
            round_num = round.id

            @service_ctrl.ensure_disable(round)
            @score_ctrl.notify_team_scores(round)

            ::VolgaCTF::Final::Model::DB.after_commit do
              @logger.info("Round #{round_num} finished!")
            end
          end

          true
        end
      end
    end
  end
end
