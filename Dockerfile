FROM docker.io/library/node:22-bookworm-slim AS assets

WORKDIR /app/assets

COPY assets/package.json assets/package-lock.json ./
RUN npm ci

FROM docker.io/library/elixir:1.18.4-otp-27-slim AS build

RUN apt-get update \
    && apt-get install --yes --no-install-recommends build-essential ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY assets assets
COPY --from=assets /app/assets/node_modules assets/node_modules
COPY lib lib
COPY priv priv

RUN mix compile
RUN mix assets.deploy

COPY config/runtime.exs config/
RUN mix release

FROM docker.io/library/debian:bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
      ca-certificates \
      gdal-bin \
      libstdc++6 \
      libtinfo6 \
      locales \
      openssl \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    PHX_SERVER=true

WORKDIR /app

RUN groupadd --system jazida \
    && useradd --system --gid jazida --home-dir /app --shell /usr/sbin/nologin jazida

COPY --from=build --chown=jazida:jazida /app/_build/prod/rel/jazida_phoenix ./

USER jazida

EXPOSE 4000

CMD ["bin/jazida_phoenix", "start"]
