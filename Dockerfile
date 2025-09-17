FROM ruby:3.2

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libpq-dev git && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile mark_x.gemspec ./
COPY lib lib
COPY db db
COPY exe exe
COPY .markx.example.yml .

RUN gem install bundler && bundle install

ENV PATH="/app/exe:${PATH}"

CMD ["mark_x", "--help"]

