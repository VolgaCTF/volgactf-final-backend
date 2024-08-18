require 'dotenv'
::Dotenv.load
require 'fileutils'

namespace :db do
  desc 'Clear database'
  task :reset do
    require 'rubygems'
    require 'sequel'

    connection_params = {
      adapter: 'postgres',
      host: ::ENV['PG_HOST'],
      port: ::ENV['PG_PORT'].to_i,
      user: ::ENV['PG_USERNAME'],
      password: ::ENV['PG_PASSWORD'],
      database: ::ENV['PG_DATABASE']
    }

    clean_query = %{
        do $$ declare
            r record;
        begin
            for r in (select tablename from pg_tables where schemaname = 'public') loop
                execute 'drop table if exists ' || quote_ident(r.tablename) || ' cascade';
        end loop;
    end $$;
    }

    ::Sequel.connect(connection_params) do |db|
      db.run clean_query
    end

    ::Sequel.extension :migration
    ::Sequel.extension :pg_json

    ::Sequel.connect(connection_params) do |db|
      ::Sequel::Migrator.run(db, 'migrations')
    end

    ::FileUtils.rm_f(::Dir.glob("#{::ENV['VOLGACTF_FINAL_TEAM_LOGO_DIR']}/*"))

    puts 'OK'
  end
end

def change_competition_stage(command)
  require './lib/model/bootstrap'
  require './lib/controller/competition'

  ::VolgaCTF::Final::Model.init
  competition_ctrl = ::VolgaCTF::Final::Controller::Competition.new

  case command
  when :init
    competition_ctrl.init
  when :start
    competition_ctrl.enqueue_start
  when :resume
    competition_ctrl.enqueue_start
  when :pause
    competition_ctrl.enqueue_pause
  when :finish
    competition_ctrl.enqueue_finish
  end

  puts 'OK'
end

namespace :competition do
  desc 'Init competition'
  task :init, [:domain] do |_, args|
    require './lib/domain/init'
    require args[:domain]
    change_competition_stage(:init)
  end

  desc 'Enqueue start competition'
  task :start do
    change_competition_stage(:start)
  end

  desc 'Resume competition'
  task :resume do
    change_competition_stage :resume
  end

  desc 'Enqueue pause competition'
  task :pause do
    change_competition_stage :pause
  end

  desc 'Enqueue finish competition'
  task :finish do
    change_competition_stage(:finish)
  end
end

def change_scoreboard_state(state)
  require './lib/model/bootstrap'
  require './lib/controller/scoreboard'

  ::VolgaCTF::Final::Model.init
  scoreboard_ctrl = ::VolgaCTF::Final::Controller::Scoreboard.new

  case state
  when :enabled
    scoreboard_ctrl.enable_broadcast
  when :disabled
    scoreboard_ctrl.disable_broadcast
  end
end

namespace :scoreboard do
  desc 'Enable scoreboard (for team and external networks)'
  task :enable do
    change_scoreboard_state(:enabled)
  end

  desc 'Disable scoreboard (for team and external networks)'
  task :disable do
    change_scoreboard_state(:disabled)
  end
end

namespace :service do
  desc 'Initialize a new service from domain file'
  task :init, [:domain] do |_, args|
    require './lib/domain/init'
    require args[:domain]
    require './lib/model/bootstrap'
    require './lib/controller/domain'

    ::VolgaCTF::Final::Model.init
    domain_ctrl = ::VolgaCTF::Final::Controller::Domain.new
    domain_ctrl.update
    puts 'OK'
  end

  desc 'Disable a service in a certain round'
  task :disable, [:alias, :round] do |_, args|
    require './lib/domain/init'
    require './lib/model/bootstrap'
    require './lib/controller/service'

    ::VolgaCTF::Final::Model.init
    service_ctrl = ::VolgaCTF::Final::Controller::Service.new
    service_ctrl.enqueue_disable(args[:alias], args[:round].to_i)
    puts 'OK'
  end

  desc 'Enable a service in a certain round'
  task :enable, [:alias, :round] do |_, args|
    require './lib/domain/init'
    require './lib/model/bootstrap'
    require './lib/controller/service'

    ::VolgaCTF::Final::Model.init
    service_ctrl = ::VolgaCTF::Final::Controller::Service.new
    service_ctrl.enqueue_enable(args[:alias], args[:round].to_i)
    puts 'OK'
  end
end

namespace :report do
  desc 'Show global stats'
  task :global_stats do
    require './lib/model/bootstrap'
    require 'terminal-table'
    require 'time_difference'
    require 'active_support/time'

    ::VolgaCTF::Final::Model.init
    ::Time.zone = 'Europe/Samara'

    rows = []

    num_teams = ::VolgaCTF::Final::Model::Team.count
    rows << ['Number of teams', num_teams]

    num_services = ::VolgaCTF::Final::Model::Service.count
    rows << ['Number of services', num_services]

    num_rounds = ::VolgaCTF::Final::Model::Round.count
    rows << ['Number of rounds', num_rounds]

    contest_started = nil
    contest_ended = nil

    ::VolgaCTF::Final::Model::CompetitionStage.all.each do |entry|
      if contest_started.nil? && entry.started?
        contest_started = entry.created_at
      end

      if contest_ended.nil? && entry.finished?
        contest_ended = entry.created_at
      end
    end

    unless contest_started.nil? || contest_ended.nil?
      cell = []
      cell << ::TimeDifference.between(contest_started, contest_ended).humanize
      cell << "from #{contest_started.in_time_zone}"
      cell << "till #{contest_ended.in_time_zone}"
      rows << ["Contest duration", cell.join("\n")]
    end

    table = ::Terminal::Table.new(
      headings: ['Parameter', 'Value'],
      rows: rows,
      style: {
        all_separators: true
      }
    )

    puts table
  end

  desc 'Show flag stats'
  task :flag_stats do
    require './lib/model/bootstrap'
    require './lib/const/team_service_state'
    require 'terminal-table'
    require 'time_difference'
    require 'active_support/time'

    ::VolgaCTF::Final::Model.init
    ::Time.zone = 'Europe/Samara'

    rows = []

    num_issued_flags = ::VolgaCTF::Final::Model::Flag.count
    rows << ['Issued flags', num_issued_flags]

    num_push_attempts_up = ::VolgaCTF::Final::Model::TeamServicePushHistoryState.where(state: ::VolgaCTF::Final::Const::TeamServiceState::UP).count
    num_push_attempts_up_rel = Float(num_push_attempts_up) * 100 / num_issued_flags
    rows << ['Number of successful push attempts', "#{num_push_attempts_up} (#{num_push_attempts_up_rel.round(2)}%)"]

    num_push_attempts_down = ::VolgaCTF::Final::Model::TeamServicePushHistoryState.where(state: ::VolgaCTF::Final::Const::TeamServiceState::DOWN).count
    num_push_attempts_down_rel = Float(num_push_attempts_down) * 100 / num_issued_flags

    num_push_attempts_mumble = ::VolgaCTF::Final::Model::TeamServicePushHistoryState.where(state: ::VolgaCTF::Final::Const::TeamServiceState::MUMBLE).count
    num_push_attempts_mumble_rel = Float(num_push_attempts_mumble) * 100 / num_issued_flags

    num_push_attempts_na = num_issued_flags - num_push_attempts_up - num_push_attempts_down - num_push_attempts_mumble
    num_push_attempts_na_rel = Float(num_push_attempts_na) * 100 / num_issued_flags

    num_push_attempts_failed = num_issued_flags - num_push_attempts_up
    num_push_attempts_failed_rel = Float(num_push_attempts_failed) * 100 / num_issued_flags
    push_attempts_failed_text = []
    push_attempts_failed_text << "#{num_push_attempts_failed} (#{num_push_attempts_failed_rel.round(2)}%)"
    push_attempts_failed_text << " DOWN #{num_push_attempts_down} (#{num_push_attempts_down_rel.round(2)}%)"
    push_attempts_failed_text << " MUMBLE #{num_push_attempts_mumble} (#{num_push_attempts_mumble_rel.round(2)}%)"
    push_attempts_failed_text << " N/A #{num_push_attempts_na} (#{num_push_attempts_na_rel.round(2)}%)"
    rows << ['Number of failed push attempts', push_attempts_failed_text.join("\n")]

    num_pull_attempts = ::VolgaCTF::Final::Model::TeamServicePullHistoryState.count
    rows << ['Number of pull attempts', num_pull_attempts]

    num_pull_attempts_up = ::VolgaCTF::Final::Model::TeamServicePullHistoryState.where(state: ::VolgaCTF::Final::Const::TeamServiceState::UP).count
    num_pull_attempts_up_rel = Float(num_pull_attempts_up) * 100 / num_pull_attempts
    rows << ['Number of successful pull attempts', "#{num_pull_attempts_up} (#{num_pull_attempts_up_rel.round(2)}%)"]

    num_pull_attempts_failed = ::VolgaCTF::Final::Model::TeamServicePullHistoryState.exclude(state: ::VolgaCTF::Final::Const::TeamServiceState::UP).count
    num_pull_attempts_failed_rel = Float(num_pull_attempts_failed) * 100 / num_pull_attempts
    pull_attempts_failed_text = []
    pull_attempts_failed_text << "#{num_pull_attempts_failed} (#{num_pull_attempts_failed_rel.round(2)}%)"

    num_pull_attempts_down = ::VolgaCTF::Final::Model::TeamServicePullHistoryState.where(state: ::VolgaCTF::Final::Const::TeamServiceState::DOWN).count
    num_pull_attempts_down_rel = Float(num_pull_attempts_down) * 100 / num_pull_attempts
    pull_attempts_failed_text << " DOWN #{num_pull_attempts_down} (#{num_pull_attempts_down_rel.round(2)}%)"

    num_pull_attempts_corrupt = ::VolgaCTF::Final::Model::TeamServicePullHistoryState.where(state: ::VolgaCTF::Final::Const::TeamServiceState::CORRUPT).count
    num_pull_attempts_corrupt_rel = Float(num_pull_attempts_corrupt) * 100 / num_pull_attempts
    pull_attempts_failed_text << " CORRUPT #{num_pull_attempts_corrupt} (#{num_pull_attempts_corrupt_rel.round(2)}%)"

    num_pull_attempts_mumble = ::VolgaCTF::Final::Model::TeamServicePullHistoryState.where(state: ::VolgaCTF::Final::Const::TeamServiceState::MUMBLE).count
    num_pull_attempts_mumble_rel = Float(num_pull_attempts_mumble) * 100 / num_pull_attempts
    pull_attempts_failed_text << " MUMBLE #{num_pull_attempts_mumble} (#{num_pull_attempts_mumble_rel.round(2)}%)"

    rows << ['Number of failed pull attempts', pull_attempts_failed_text.join("\n")]

    table = ::Terminal::Table.new(
      headings: ['Parameter', 'Value'],
      rows: rows,
      style: {
        all_separators: true
      }
    )

    puts table
  end


  desc 'Show attack stats'
  task :attack_stats do
    require './lib/model/bootstrap'
    # require './lib/const/team_service_state'
    require 'terminal-table'
    require 'active_support/time'

    ::VolgaCTF::Final::Model.init
    ::Time.zone = 'Europe/Samara'

    rows = []

    num_attack_attempts = ::VolgaCTF::Final::Model::AttackAttempt.count
    rows << ['Number of attack attempts', num_attack_attempts]

    num_attacks = ::VolgaCTF::Final::Model::Attack.count
    num_attacks_rel = Float(num_attacks) * 100 / num_attack_attempts
    rows << ['Number of successful attacks', "#{num_attacks} (#{num_attacks_rel.round(2)}%)"]

    failed_categories = {
      ::VolgaCTF::Final::Const::SubmitResult::ERROR_FLAG_INVALID => 'ERROR_FLAG_INVALID',
      ::VolgaCTF::Final::Const::SubmitResult::ERROR_RATELIMIT => 'ERROR_RATELIMIT',
      ::VolgaCTF::Final::Const::SubmitResult::ERROR_FLAG_EXPIRED => 'ERROR_FLAG_EXPIRED',
      ::VolgaCTF::Final::Const::SubmitResult::ERROR_FLAG_YOUR_OWN => 'ERROR_FLAG_YOUR_OWN',
      ::VolgaCTF::Final::Const::SubmitResult::ERROR_FLAG_SUBMITTED => 'ERROR_FLAG_SUBMITTED',
      ::VolgaCTF::Final::Const::SubmitResult::ERROR_FLAG_NOT_FOUND => 'ERROR_FLAG_NOT_FOUND',
      ::VolgaCTF::Final::Const::SubmitResult::ERROR_SERVICE_STATE_INVALID => 'ERROR_SERVICE_STATE_INVALID'
    }

    failed_categories.each do |category, description|
      absolute_value = ::VolgaCTF::Final::Model::AttackAttempt.where(response: category).count
      relative_value = Float(absolute_value) * 100 / num_attack_attempts
      rows << [
        "Number of failed attack attempts (#{description})",
        "#{absolute_value} (#{relative_value.round(2)}%)"
      ]
    end

    table = ::Terminal::Table.new(
      headings: ['Parameter', 'Value'],
      rows: rows,
      style: {
        all_separators: true
      }
    )

    puts table
  end

  desc 'Show services which have been attacked by teams'
  task :team_services do
    require './lib/model/bootstrap'
    ::VolgaCTF::Final::Model.init

    report = {}

    ::VolgaCTF::Final::Model::Team.all.each do |team|
      report[team.id] = Set.new
    end

    ::VolgaCTF::Final::Model::Attack.all.each do |attack|
      flag = ::VolgaCTF::Final::Model::Flag[attack.flag_id]
      report[attack.team_id].add(flag.service_id)
    end

    require 'terminal-table'
    rows = []
    report.each do |team_id, service_list|
      row = []
      row << ::VolgaCTF::Final::Model::Team[team_id].name
      services = service_list.map do |service_id|
        ::VolgaCTF::Final::Model::Service[service_id].name
      end
      row << services.join("\n")
      rows << row
    end

    table = ::Terminal::Table.new(
      headings: ['Team', 'Services'],
      rows: rows,
      style: {
        all_separators: true
      }
    )

    puts table
  end
end
