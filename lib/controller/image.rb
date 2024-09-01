require 'digest'

require './lib/util/logger'
require './lib/queue/tasks'
require './lib/util/event_emitter'

module VolgaCTF
  module Final
    module Controller
      class Image
        def initialize
          @logger = ::VolgaCTF::Final::Util::Logger.get
        end

        def load(path)
          image = nil
          begin
            image = ::MiniMagick::Image.open(path)
          rescue => e
            @logger.error(e.to_s)
          end

          image
        end

        def perform_resize(path, team_id)
          ::VolgaCTF::Final::Queue::Tasks::ResizeImage.perform_async(path, team_id)
        end

        def resize(path, team)
          begin
            image = ::MiniMagick::Image.open(path)
            image.resize('48x48')
            image.format('png')
            image_path = ::File.join(::ENV['VOLGACTF_FINAL_TEAM_LOGO_DIR'], "#{team.id}.png")
            image.write(image_path)
            ::File.chmod(0666, image_path)
            sha256 = ::Digest::SHA256.file(image_path)

            ::VolgaCTF::Final::Model::DB.transaction do
              team.logo_hash = sha256.hexdigest
              team.save

              ::VolgaCTF::Final::Util::EventEmitter.broadcast(
                'team/modify',
                team.serialize
              )
            end
          rescue => e
            @logger.error(e.to_s)
          end
        end
      end
    end
  end
end
