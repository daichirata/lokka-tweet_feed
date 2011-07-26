require 'oauth'

module Lokka
  module TweetFeed
    CONSUMER_KEY = "ZcvJedKCxb0FCKSCpZDJJA"
    CONSUMER_SECRET = "4PcwMbOsmn5FZbZ13R8ZKOL9asvSIV85bfnS4YbnYZI"

    def self.registered(app)
      app.get '/admin/plugins/tweet_feed' do
        erb %{ <a href="/admin/plugins/tweet_feed/request_token">OAuth Login</a> }
      end

      app.get '/admin/plugins/tweet_feed/request_token' do
        consumer = OAuth::Consumer.new(CONSUMER_KEY, CONSUMER_SECRET, :site => "http://twitter.com")
        url = "#{request.scheme}://#{request.host}"

          request_token = consumer.get_request_token(
            :oauth_callback => url + "/admin/plugins/tweet_feed/oauth_callback"
          )
          session[:request_token] = request_token.token
          session[:request_token_secret] = request_token.secret
          redirect request_token.authorize_url
      end

      app.get '/admin/plugins/tweet_feed/oauth_callback' do
        consumer = OAuth::Consumer.new(CONSUMER_KEY, CONSUMER_SECRET, :site => "http://twitter.com")
        request_token = OAuth::RequestToken.new(
          consumer,
          session[:request_token],
          session[:request_token_secret]
        )
        begin
          @access_token = request_token.get_access_token(
            {},
            :oauth_token => params[:oauth_token],
            :oauth_verifier => params[:oauth_verifier]
          )
        rescue OAuth::Unauthorized => @exception
          return erb %{ oauth faild: <%=h @exception.message %>}
        end

        Option.tweet_feed_token = @access_token.token
        Option.tweet_feed_secret = @access_token.secret

        erb %{
              oauth success!
              <dl>
                <dt>access token</dt>
                <dd><%=h @access_token.token %></dd>
                <dt>secret</dt>
                <dd><%=h @access_token.secret %></dd>
              </dl>
        }
      end
    end#registered
  end#TweetFeed
end#Lokka
