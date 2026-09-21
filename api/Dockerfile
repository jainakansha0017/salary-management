# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.1.0
FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim as base

# Rails app lives here
WORKDIR /rails

# Set production environment.
#
# `development:test`, not the generated `development`. This Gemfile has a real
# test group, and pg_query in it vendors and compiles libpg_query — minutes of
# build time and a peak memory spike, to install a gem that only ever runs
# under RSpec. A gem in both groups, like rspec-rails, is excluded only because
# both of its groups are.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"


# Throw-away build stage to reduce size of final image
FROM base as build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev pkg-config

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/


# Final stage for app image
FROM base

# Install packages needed for deployment.
#
# postgresql-client is not optional here. `schema_format = :sql`, and Rails
# loads a structure.sql by shelling out to `psql` — without it the first boot
# cannot create the schema at all.
#
# curl was in the generated Dockerfile to serve a HEALTHCHECK directive this
# image does not have; nothing in the app or the entrypoint calls it, and the
# platform checks /up over the network. It is dropped rather than pinned,
# because ruby:3.1.0-slim is a bullseye image old enough that its package index
# points at curl builds security.debian.org has since superseded — apt resolves
# 7.74.0-1.3+deb11u16 and the pool answers 404. An unused package is not worth
# a workaround.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy built artifacts: gems, application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security
RUN useradd rails --create-home --shell /bin/bash && \
    chown -R rails:rails db log tmp
USER rails:rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["./bin/rails", "server"]
