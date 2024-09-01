require 'sinatra/base'
require 'sinatra/json'
require 'json'
require 'ip'
require 'date'
require 'mini_magick'

require './lib/controller/attack'
require './lib/util/event_emitter'
require './lib/model/bootstrap'
require './lib/controller/ctftime'
require './lib/const/submit_result'
require './lib/const/service_status'

require './lib/controller/identity'
require './lib/controller/competition'
require './lib/controller/competition_stage'
require './lib/controller/scoreboard'
require './lib/controller/image'
require './lib/controller/score'
require './lib/controller/team_service_state'

module VolgaCTF
  module Final
    module Server
      class Application < ::Sinatra::Base
        disable :run
        disable :method_override
        disable :static

        set :environment, ::ENV['APP_ENV']

        def initialize(app = nil)
          super(app)

          @identity_ctrl = ::VolgaCTF::Final::Controller::Identity.new
          @ctftime_ctrl = ::VolgaCTF::Final::Controller::CTFTime.new
          @competition_stage_ctrl = ::VolgaCTF::Final::Controller::CompetitionStage.new
          @competition_ctrl = ::VolgaCTF::Final::Controller::Competition.new
          @attack_ctrl = ::VolgaCTF::Final::Controller::Attack.new
          @scoreboard_ctrl = ::VolgaCTF::Final::Controller::Scoreboard.new
          @image_ctrl = ::VolgaCTF::Final::Controller::Image.new
          @score_ctrl = ::VolgaCTF::Final::Controller::Score.new
          @team_service_state_ctrl = ::VolgaCTF::Final::Controller::TeamServiceState.new

          ::MiniMagick.configure do |config|
            config.cli = :graphicsmagick
          end
        end

        configure do
          ::VolgaCTF::Final::Model.init
        end

        configure :production, :development do
          enable :logging
        end

        before do
          @remote_ip = ::IP.new(request.ip)
        end

        get '/api/identity' do
          identity = nil

          identity_team = @identity_ctrl.get_team(@remote_ip)
          unless identity_team.nil?
            identity = { name: 'team', id: identity_team.id }
          end

          if identity.nil? && @identity_ctrl.is_internal?(@remote_ip)
            identity = { name: 'internal' }
          end

          if identity.nil?
            identity = { name: 'external' }
          end

          json identity
        end

        get '/api/competition/round' do
          round = ::VolgaCTF::Final::Model::Round.count
          json(value: (round == 0) ? nil : round)
        end

        get '/api/competition/stage' do
          json(value: @competition_stage_ctrl.current.stage)
        end

        get '/api/scoreboard' do
          muted = \
            if @identity_ctrl.is_internal?(@remote_ip)
              false
            else
              !@scoreboard_ctrl.broadcast?
            end

          if muted
            obj = ::VolgaCTF::Final::Model::ScoreboardHistoryPosition.last
          else
            obj = ::VolgaCTF::Final::Model::ScoreboardPosition.last
          end

          json(
            muted: muted,
            positions: obj.nil? ? {} : obj.data
          )
        end

        get '/api/teams' do
          json ::VolgaCTF::Final::Model::Team.ordered.map { |t| t.serialize }
        end

        get '/api/services' do
          json ::VolgaCTF::Final::Model::Service.enabled.map { |s| s.serialize }
        end

        get '/api/service/index' do
          unless @identity_ctrl.is_internal?(@remote_ip)
            halt 401
          end

          json ::VolgaCTF::Final::Model::Service.map { |s| s.serialize }
        end

        get %r{/api/team/(\d{1,2})/stats} do |team_id_str|
          unless @identity_ctrl.is_internal?(@remote_ip)
            halt 401
          end

          team_id = team_id_str.to_i
          team = ::VolgaCTF::Final::Model::Team[team_id]
          halt 404 if team.nil?

          json @score_ctrl.get_team_scores(team).map { |s| s.serialize }
        end

        get '/api/team/stats' do
          team = @identity_ctrl.get_team(@remote_ip)

          if team.nil?
            halt 401, 'Unauthorized'
          end

          json @score_ctrl.get_team_scores(team).map { |s| s.serialize }
        end

        get '/api/team/service/push-states' do
          identity = nil

          identity_team = @identity_ctrl.get_team(@remote_ip)
          unless identity_team.nil?
            identity = { name: 'team', id: identity_team.id }
          end

          if identity.nil? && @identity_ctrl.is_internal?(@remote_ip)
            identity = { name: 'internal' }
          end

          if identity.nil?
            identity = { name: 'external' }
          end

          json ::VolgaCTF::Final::Model::TeamServicePushState.map { |team_service_state|
            {
              id: team_service_state.id,
              team_id: team_service_state.team_id,
              service_id: team_service_state.service_id,
              state: team_service_state.state,
              message: (identity[:name] == 'internal' || (identity[:name] == 'team' && identity[:id] == team_service_state.team_id)) ? team_service_state.message : nil,
              updated_at: team_service_state.updated_at.iso8601
            }
          }
        end

        get '/api/team/service/pull-states' do
          identity = nil

          identity_team = @identity_ctrl.get_team(@remote_ip)
          unless identity_team.nil?
            identity = { name: 'team', id: identity_team.id }
          end

          if identity.nil? && @identity_ctrl.is_internal?(@remote_ip)
            identity = { name: 'internal' }
          end

          if identity.nil?
            identity = { name: 'external' }
          end

          json ::VolgaCTF::Final::Model::TeamServicePullState.map { |team_service_state|
            {
              id: team_service_state.id,
              team_id: team_service_state.team_id,
              service_id: team_service_state.service_id,
              state: team_service_state.state,
              message: (identity[:name] == 'internal' || (identity[:name] == 'team' && identity[:id] == team_service_state.team_id)) ? team_service_state.message : nil,
              updated_at: team_service_state.updated_at.iso8601
            }
          }
        end

        post '/api/flag/v1/submit' do
          content_type :text
          unless request.content_type == 'text/plain'
            halt 400, ::VolgaCTF::Final::Const::SubmitResult.key(
              ::VolgaCTF::Final::Const::SubmitResult::ERROR_FLAG_INVALID).to_s
          end

          team = @identity_ctrl.get_team(@remote_ip)

          if team.nil?
            halt 400, ::VolgaCTF::Final::Const::SubmitResult.key(
              ::VolgaCTF::Final::Const::SubmitResult::ERROR_ACCESS_DENIED).to_s
          end

          payload = nil

          begin
            request.body.rewind
            flag_str = request.body.read
          rescue => e
            halt 400, ::VolgaCTF::Final::Const::SubmitResult.key(
              ::VolgaCTF::Final::Const::SubmitResult::ERROR_FLAG_INVALID).to_s
          end

          stage = @competition_stage_ctrl.current
          if stage.not_started? || stage.starting?
            halt 400, ::VolgaCTF::Final::Const::SubmitResult.key(
              ::VolgaCTF::Final::Const::SubmitResult::ERROR_COMPETITION_NOT_STARTED).to_s
          end

          if stage.paused?
            halt 400, ::VolgaCTF::Final::Const::SubmitResult.key(
              ::VolgaCTF::Final::Const::SubmitResult::ERROR_COMPETITION_PAUSED).to_s
          end

          if stage.finished?
            halt 400, ::VolgaCTF::Final::Const::SubmitResult.key(
              ::VolgaCTF::Final::Const::SubmitResult::ERROR_COMPETITION_FINISHED).to_s
          end

          r = @attack_ctrl.handle(stage, team, flag_str)
          ::VolgaCTF::Final::Const::SubmitResult.key(r).to_s
        end

        get %r{/api/flag/v1/info/([\da-f]{32}=)} do |flag_str|
          flag_obj = ::VolgaCTF::Final::Model::Flag.exclude(
            pushed_at: nil
          ).where(
            flag: flag_str
          ).first

          halt 404 if flag_obj.nil?

          r = {
            flag: flag_obj.flag,
            nbf: flag_obj.pushed_at.iso8601,
            exp: flag_obj.expired_at.iso8601,
            round: flag_obj.round_id,
            team: flag_obj.team.name,
            service: flag_obj.service.name
          }

          json r
        end

        helpers do
          def internal_protected!
            return if internal_authorized?
            headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
            halt 401, "Not authorized\n"
          end

          def internal_authorized?
            @auth ||= Rack::Auth::Basic::Request.new(request.env)
            @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == [::ENV['VOLGACTF_FINAL_AUTH_MASTER_USERNAME'], ::ENV['VOLGACTF_FINAL_AUTH_MASTER_PASSWORD']]
          end
        end

        post '/api/checker/v2/report_push' do
          internal_protected!
          unless request.content_type == 'application/json'
            halt 400
          end

          payload = nil

          begin
            request.body.rewind
            payload = ::JSON.parse(request.body.read)
          rescue => e
            halt 400
          end

          begin
            flag = ::VolgaCTF::Final::Model::Flag.first(
              flag: payload['flag']
            )
            if flag.nil?
              halt 400
            else
              @competition_ctrl.handle_push(
                flag,
                payload['status'],
                payload['label'],
                payload['message']
              )
            end
          rescue => e
            halt 400
          end

          status 204
          body ''
        end

        post '/api/checker/v2/report_pull' do
          internal_protected!
          unless request.content_type == 'application/json'
            halt 400
          end

          payload = nil

          begin
            request.body.rewind
            payload = ::JSON.parse request.body.read
          rescue => e
            halt 400
          end

          begin
            poll = ::VolgaCTF::Final::Model::FlagPoll.first(
              id: payload['request_id']
            )
            if poll.nil?
              halt 400
            else
              @competition_ctrl.handle_pull(
                poll,
                payload['status'],
                payload['message']
              )
            end
          rescue => e
            halt 400
          end

          status 204
          body ''
        end
      end
    end
  end
end

require './lib/route/public_capsule'
require './lib/route/public_ctftime'
require './lib/route/public_service'
require './lib/route/notification'
require './lib/route/team_logo'
require './lib/route/event'
