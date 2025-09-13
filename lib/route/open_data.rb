require 'sinatra/base'

module VolgaCTF
  module Final
    module Server
      class Application < ::Sinatra::Base
        get '/api/open_data/v1' do
          json @open_data_ctrl.fetch_open_data
        end
      end
    end
  end
end
