require 'sinatra/base'
require 'tempfile'

require './lib/model/bootstrap'
require './lib/util/tempfile_monkey_patch'

module VolgaCTF
  module Final
    module Server
      class Application < ::Sinatra::Base
        post '/api/team/logo' do
          team = @identity_ctrl.get_team(@remote_ip)

          if team.nil?
            halt 401, 'Unauthorized'
          end

          unless params[:file]
            halt 400, 'No file'
          end

          path = nil
          upload = params[:file][:tempfile]
          extension = ::File.extname(params[:file][:filename])
          t = Tempfile.open(['logo', extension], ::ENV['VOLGACTF_FINAL_UPLOAD_DIR']) do |f|
            f.write(upload.read)
            path = f.path
            f.persist  # introduced by a monkey patch
          end

          image = @image_ctrl.load(path)
          if image.nil?
            halt 400, 'Error processing image'
          end

          if image.width != image.height
            halt 400, 'Image width must equal its height'
          end

          @image_ctrl.perform_resize(path, team.id)
          status 201
          headers 'Location' => "/api/team/logo/#{team.id}.png"
          body ''
        end
      end
    end
  end
end
