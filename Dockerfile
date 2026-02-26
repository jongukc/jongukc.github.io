FROM ruby:2.7-alpine3.16

RUN apk update
RUN set -ex
RUN apk add --no-cache sudo build-base gcc cmake git python3

RUN gem install bundler -v 2.4.22

# dependencies for jekyll
RUN gem install ffi -v 1.16.3
RUN gem install public_suffix -v 4.0.7

RUN gem install jekyll -v 3.9.3
RUN gem update bundler

COPY Gemfile Gemfile.lock ./
RUN bundle install

ENV USER=blog
ENV GROUP=$USER

RUN addgroup \
    "$GROUP" \
&&  adduser \
    --disabled-password \
    --ingroup "$GROUP" \
    $USER

RUN echo "$USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USER && chmod 0440 /etc/sudoers.d/$USER

USER ${USER}:${GROUP}
WORKDIR /home/${USER}/workspace
