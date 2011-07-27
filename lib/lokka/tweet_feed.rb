require 'oauth'
require 'twitter'
require 'json'

module Lokka
  module TweetFeed
    CONSUMER_KEY = "iBhYRxPYM89O0jjzYOgYEA"
    CONSUMER_SECRET = "lxfRU4srZqfP7JEIEkFj8UywCeJuXCOooETF1xtl11g"

    def self.registered(app)
      app.get '/admin/plugins/tweet_feed' do
        haml  :"plugin/lokka-tweet_feed/views/index", :layout => :"admin/layout"
      end

      app.put '/admin/plugins/tweet_feed' do
        Option.tweet_feed_short_url = params['tweet_feed_short_url']
        Option.tweet_feed_bitly_user_id = params['tweet_feed_bitly_user_id']
        Option.tweet_feed_bitly_api_key = params['tweet_feed_bitly_api_key']
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
          access_token = request_token.get_access_token(
            {},
            :oauth_token => params[:oauth_token],
            :oauth_verifier => params[:oauth_verifier]
          )
        rescue OAuth::Unauthorized
          flash[:error] = "It failed in the attestation."
          redirect '/admin/plugins/tweet_feed'
        end

        Option.tweet_feed_token = access_token.token
        Option.tweet_feed_secret = access_token.secret

        redirect '/admin/plugins/tweet_feed'
      end

      app.post '/admin/posts' do
        @post = Post.new(params['post'])
        @post.user = current_user
        if @post.save
          flash[:notice] = t.post_was_successfully_created
          url = "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}"
          Lokka::TweetFeed.twitter_post(@post, url)
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

      app.put '/admin/posts/:id' do |id|
        @post = Post.get(id)
        if @post.update(params['post'])
          flash[:notice] = t.post_was_successfully_updated
          url = "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}"
          Lokka::TweetFeed.twitter_put(@post, url)
          if @post.draft
            redirect '/admin/posts?draft=true'
          else
            redirect '/admin/posts'
          end
        else
          @categories = Category.all.map {|c| [c.id, c.title] }.unshift([nil, t.not_select])
          render_any :'posts/edit'
        end
      end

      app.delete '/admin/posts/:id' do |id|
        post = Post.get(id)
        Lokka::TweetFeed.reject_id(post.id)
        post.destroy
        flash[:notice] = t.post_was_successfully_deleted
        if post.draft
          redirect '/admin/posts?draft=true'
        else
          redirect '/admin/posts'
        end
      end
    end

    def self.consumer
      OAuth::Consumer.new(CONSUMER_KEY, CONSUMER_SECRET, :site => "http://twitter.com")
    end

    def self.twitter_configure
      Twitter.configure do |config|
        config.consumer_key = CONSUMER_KEY
        config.consumer_secret = CONSUMER_SECRET
        config.oauth_token = Option.tweet_feed_token
        config.oauth_token_secret = Option.tweet_feed_secret
      end
    end

    def self.bitly_short_url(long_url)
      begin
        return if !Option.tweet_feed_bitly_user_id && !Option.tweet_feed_bitly_api_key
        user_id = Option.tweet_feed_bitly_user_id
        api_key = Option.tweet_feed_bitly_api_key

        query = "version=2.0.1&longUrl=#{long_url}&login=#{user_id}&apiKey=#{api_key}"
        results = JSON.parse(Net::HTTP.get("api.bit.ly", "/shorten?#{query}"))
        results["results"][long_url]["shortUrl"]
      rescue
        long_url
      end
    end

    def self.tiny_short_url(long_url)
      begin
        query = "url=#{URI.encode(long_url)}"
        Net::HTTP.get("tinyurl.com", "/api-create.php?#{query}")
      rescue
        return long_url
      end
    end

    def self.short_url(long_url)
      if Option.tweet_feed_short_url == "bitly"
        Lokka::TweetFeed.bitly_short_url(long_url)
      else
        Lokka::TweetFeed.tiny_short_url(long_url)
      end
    end

    def self.twitter_post(post, url)
      return unless Option.tweet_feed_token && Option.tweet_feed_secret
      post.reload
      if post.draft
        Lokka::TweetFeed.check_draft(post.id)
      else
        Lokka::TweetFeed.update(post, url)
      end
    end

    def self.twitter_put(post, url)
      return unless Lokka::TweetFeed.uncontribution?(post.id)
      unless post.draft
        Lokka::TweetFeed.update(post,url)
      end
    end

    def self.update(post, long_url)
      site = Site.first
      url = long_url + "/#{post.id}"
      short_url = Lokka::TweetFeed.short_url(url)
      Lokka::TweetFeed.twitter_configure
      Twitter.update("#{Option.tweet_feed_post_message}: #{post.title} - #{site.title} #{short_url}")
      Lokka::TweetFeed.reject_id(post.id)
    end

    def self.check_draft(id)
      if Option.tweet_feed_uncontribution 
        uncont = Lokka::TweetFeed.get_uncontribution_id
        uncont << id
        Option.tweet_feed_uncontribution = uncont
      else 
        Option.tweet_feed_uncontribution = [id]
      end
    end

    def self.reject_id(id)
      if Option.tweet_feed_token && Option.tweet_feed_secret && Lokka::TweetFeed.uncontribution?(id)
        Option.tweet_feed_uncontribution = Lokka::TweetFeed.get_uncontribution_id.reject{|i| i == id}
      end
    end

    def self.uncontribution?(id)
      Option.tweet_feed_uncontribution ? Lokka::TweetFeed.get_uncontribution_id.include?(id) : false
    end

    def self.get_uncontribution_id
      result = Option.tweet_feed_uncontribution 
      eval(result)
    end
  end
end
