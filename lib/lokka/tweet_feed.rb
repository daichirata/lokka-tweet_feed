require 'oauth'
require 'twitter'

module Lokka
  module TweetFeed
    CONSUMER_KEY = "iBhYRxPYM89O0jjzYOgYEA"
    CONSUMER_SECRET = "lxfRU4srZqfP7JEIEkFj8UywCeJuXCOooETF1xtl11g"

    def self.consumer
      OAuth::Consumer.new( CONSUMER_KEY, CONSUMER_SECRET, :site => "http://twitter.com")
    end

    def self.twitter_configure
      Twitter.configure do |config|
        config.consumer_key = CONSUMER_KEY
        config.consumer_secret = CONSUMER_SECRET
        config.oauth_token = Option.tweet_feed_token
        config.oauth_token_secret = Option.tweet_feed_secret
      end
    end

    def self.twitter_update(title,url)
      site = Site.first
      Lokka::TweetFeed.twitter_configure
      Twitter.update("#{Option.tweet_feed_post_message}: #{title} - #{site.title} #{Lokka::TweetFeed.tiny_short_url(url)}")
    end

    def self.tiny_short_url(url)
      query = "url=#{URI.encode(url)}"
      Net::HTTP.get("tinyurl.com", "/api-create.php?#{query}")
    end

    def self.attestation?
      Option.tweet_feed_token && Option.tweet_feed_secret
    end

    def self.registered(app)
      app.get '/admin/plugins/tweet_feed' do
        haml  :"plugin/lokka-tweet_feed/views/index", :layout => :"admin/layout"
      end

      app.put '/admin/plugins/tweet_feed' do
        Option.tweet_feed_post_message = params['tweet_feed_post_message']
        flash[:notice] = 'Updated.'
        redirect '/admin/plugins/tweet_feed'
      end

      app.get '/admin/plugins/tweet_feed/request_token' do
        callback_url = "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}/admin/plugins/tweet_feed/oauth_callback"

        request_token = Lokka::TweetFeed.consumer.get_request_token(:oauth_callback => callback_url)
        session[:request_token] = request_token.token
        session[:request_token_secret] = request_token.secret
        redirect request_token.authorize_url
      end

      app.get '/admin/plugins/tweet_feed/oauth_callback' do
        request_token = OAuth::RequestToken.new(
          Lokka::TweetFeed.consumer,
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
          flash[:error] = "It failed in the attestation."
          redirect '/admin/plugins/tweet_feed'
        end

        Option.tweet_feed_token = @access_token.token
        Option.tweet_feed_secret = @access_token.secret

        redirect '/admin/plugins/tweet_feed'
      end

      app.post '/admin/posts' do
        @post = Post.new(params['post'])
        @post.user = current_user
        if @post.save
          flash[:notice] = t.post_was_successfully_created
          if Lokka::TweetFeed.attestation?
            @post.reload
            url = "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}/#{@post.id}"
            Lokka::TweetFeed.twitter_update(@post.title,url)
          end
          if @post.draft
            redirect '/admin/posts?draft=true'
          else
            redirect '/admin/posts'
          end
        else
          @categories = Category.all.map {|c| [c.id, c.title] }.unshift([nil, t.not_select])
          render_any :'posts/new'
        end
      end
    end
  end
end
