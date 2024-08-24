FROM ruby:2.7-alpine3.16

RUN apk update
RUN apk add --no-cache build-base gcc cmake git

RUN gem install bundler -v 2.4.22

# dependencies for jekyll
RUN gem install ffi -v 1.16.3
RUN gem install public_suffix -v 4.0.7

RUN gem install jekyll -v 3.9.3
RUN gem update bundler 
