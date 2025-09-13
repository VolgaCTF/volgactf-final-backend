require 'date'
require 'openssl'
require 'securerandom'
require 'digest/md5'
require 'base64'

require 'jwt'

require './lib/util/logger'

module VolgaCTF
  module Final
    module Controller
      class Flag
        def initialize
          @logger = ::VolgaCTF::Final::Util::Logger.get
          @key = ::OpenSSL::PKey.read(::ENV['VOLGACTF_FINAL_FLAG_SIGN_KEY_PRIVATE'].gsub('\n', "\n"))
          @alg = 'none'
          if @key.class == ::OpenSSL::PKey::RSA
            @alg = 'RS256'
          elsif @key.class == ::OpenSSL::PKey::EC
            @alg = 'ES256'
          end

          @prefix = ::ENV['VOLGACTF_FINAL_FLAG_WRAP_PREFIX']
          @suffix = ::ENV['VOLGACTF_FINAL_FLAG_WRAP_SUFFIX']
          @generator_secret = ::Base64.urlsafe_decode64(
            ::ENV['VOLGACTF_FINAL_FLAG_GENERATOR_SECRET']
          )
        end

        def issue(team, service, round)
          model = nil

          ::VolgaCTF::Final::Model::DB.transaction do
              flag, label = generate_flag_label
              created = ::DateTime.now
              model = ::VolgaCTF::Final::Model::Flag.create(
                flag: flag,
                created_at: created,
                pushed_at: nil,
                expired_at: nil,
                label: label,
                capsule: encode(flag),
                open_data: nil,
                service_id: service.id,
                team_id: team.id,
                round_id: round.id
              )
          end

          model
        end

        private
        def encode(s)
          "#{@prefix}#{::JWT.encode({'flag' => s}, @key, @alg)}#{@suffix}"
        end

        def generate_flag_label
          src = ::Digest::MD5.new
          src << ::SecureRandom.random_bytes(32)
          src << @generator_secret
          flag = "#{src.hexdigest}="
          label = ::SecureRandom.uuid
          return flag, label
        end
      end
    end
  end
end
