FROM elixir:1.17-otp-27-alpine AS builder

WORKDIR /app

RUN apk add --no-cache build-base git

COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get --only prod

ENV MIX_ENV=prod
COPY . .
RUN mix compile
RUN mix phx.digest
RUN mix release

# --- Runtime ---
FROM elixir:1.17-otp-27-alpine

WORKDIR /app

RUN apk add --no-cache ncurses-libs libstdc++ libgcc

COPY --from=builder /app/_build/prod/rel/prostaff_events ./

ENV HOME=/app
ENV MIX_ENV=prod
ENV PORT=4000

EXPOSE 4000

CMD ["bin/prostaff_events", "start"]
