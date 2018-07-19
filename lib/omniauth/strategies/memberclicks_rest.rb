require 'omniauth-oauth2'

module OmniAuth
  module Strategies
    class MemberclicksREST < OmniAuth::Strategies::OAuth2
      option :name, 'memberclicks_rest'

      option :client_options, {
        authorize_url: '/oauth/v1/authorize',
        custom_field_keys: [],
        site: 'MUST_BE_PROVIDED',
        token_url: '/oauth/v1/token',
        user_info_url: '/api/v1/profile/me'
      }

      uid { info[:uid] }

      info { raw_user_info }

      def request_phase
        redirect client.auth_code.authorize_url({ redirect_uri: "#{callback_url}?slug=#{account_slug}" }.merge(authorize_params))
      end

      def callback_phase
        return fail!(:invalid_credentials) unless request.params['code']
        account = Account.find_by(slug: account_slug)
        @app_event = account.app_events.create(activity_type: 'sso')

        request_log = "[MemberclicksREST] Authenticate Request:\nPOST #{options.client_options.token_url}"
        @app_event.logs.create(level: 'info', text: request_log)

        response = connection.post(options.client_options.token_url) do |request|
          request.headers['Authorization'] = auth_header
          request.headers['Content-Type'] = 'application/x-www-form-urlencoded'
          request.body = auth_body
        end

        response_log = "[MemberclicksREST] Authenticate Response (code: #{response.status}):\n#{response.inspect}"

        if response.success?
          @app_event.logs.create(level: 'info', text: response_log)
          prepare_access_token(response.body)
          self.env['omniauth.origin'] = '/' + account_slug
          self.env['omniauth.auth'] = auth_hash

          finalize_app_event
          call_app!
        else
          @app_event.logs.create(level: 'error', text: response_log)
          @app_event.fail!
          fail!(:invalid_credentials)
        end
      end

      private

      def account_slug
        request.params['slug'] || session['omniauth.params']['origin'].gsub(/\//,'')
      end

      def auth_body
        {
          grant_type: 'authorization_code',
          code: request.params['code'],
          redirect_uri: "#{callback_url}?slug=#{account_slug}"
        }.to_param
      end

      def auth_hash
        AuthHash.new(provider: name, uid: uid, info: info)
      end

      def auth_header
        hash = Base64.encode64(options[:client_id] + ':' + options[:client_secret]).delete("\n")
        "Basic #{hash}"
      end

      def connection
        Faraday.new(url: options.client_options.site) do |request|
          request.headers['Accept'] = 'application/json'
          request.adapter(Faraday.default_adapter)
        end
      end

      def custom_fields_data(parsed_response)
        custom_field_keys = options.client_options.custom_field_keys.to_a

        parsed_response.each_with_object({}) do |(key, value), memo|
          next unless custom_field_keys.include?(key)
          memo[key.downcase] = value
        end
      end

      def finalize_app_event
        app_event_data = {
          user_info: {
            uid: uid,
            first_name: info[:first_name],
            last_name: info[:last_name],
            email: info[:email]
          }
        }

        @app_event.update(raw_data: app_event_data)
      end

      def prepare_access_token(raw_body)
        response_body = MultiJson.load(raw_body)

        self.access_token = {
          token: response_body['access_token'],
          token_expires: response_body['expires_in'],
          refresh_token: response_body['refresh_token']
        }
      end

      def prepare_user_info(raw_body)
        return @user_info if defined?(@user_info)
        parsed_body = MultiJson.load(raw_body)

        @user_info = {
          first_name: parsed_body['[Name | First]'],
          last_name: parsed_body['[Name | Last]'],
          email: parsed_body['[Email | Primary]'],
          username: parsed_body['[Username]'],
          uid: parsed_body['[Profile ID]'].to_s,
          member_status: parsed_body['[Member Status]'],
          member_type: parsed_body['[Member Type]'],
          custom_fields_data: custom_fields_data(parsed_body)
        }
      end

      def raw_user_info
        return @raw_user_info if defined?(@raw_user_info)

        request_log = "[MemberclicksREST] User profile Request:\nGET #{user_info_url}"
        @app_event.logs.create(level: 'info', text: request_log)
        response = connection.get(user_info_url) do |request|
          request.headers['Authorization'] = "Bearer #{access_token[:token]}"
        end

        response_log = "[MemberclicksREST] User profile Response (code: #{response.status}):\n#{response.inspect}"

        if response.success?
          @app_event.logs.create(level: 'info', text: response_log)
        else
          @app_event.logs.create(level: 'error', text: response_log)
          @app_event.fail!
          return fail!(:invalid_credentials)
        end

        @raw_user_info ||= prepare_user_info(response.body)
      end

      def user_info_url
        options.client_options.user_info_url
      end
    end
  end
end
