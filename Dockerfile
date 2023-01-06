FROM ruby:latest

RUN mkdir /app
WORKDIR /app

ADD Gemfile /app
ADD rack_dav.gemspec /app
ADD lib/rack_dav/version.rb /app/lib/rack_dav/version.rb

RUN bundle install

ADD . /app

