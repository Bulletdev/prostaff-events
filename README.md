# prostaff-events

Real-time event bus and WebSocket hub for the ProStaff ecosystem.

Built with Elixir/Phoenix. Subscribes to Redis pub/sub channels published by the Rails API and
delivers events to connected clients via Phoenix Channels (WebSocket).

## Architecture

```
Rails API  ──publish──▶  Redis pub/sub  ──subscribe──▶  prostaff-events
                                                              │
                              ┌───────────────────────────────┤
                              ▼                               ▼
                       Phoenix Channels                InhouseQueue
                    (NotificationChannel,               GenServer
                     TournamentChannel,               (one per active
                     InhouseChannel)                     queue)
                              │
                              ▼
                    Connected clients
                   (Next.js frontend,
                    Discord bot)
```

Redis channel format: `prostaff:events:{org_id}`

## Channels

| Channel topic          | Who subscribes         | Auth requirement                     |
|------------------------|------------------------|--------------------------------------|
| `notifications:{uid}`  | Logged-in users        | JWT — user_id must match topic       |
| `tournament:{id}`      | Any authenticated user | JWT                                  |
| `inhouse:{org_id}`     | Org members            | JWT — org_id must match topic        |

## Environment Variables

| Variable               | Required | Description                                          |
|------------------------|----------|------------------------------------------------------|
| `REDIS_URL`            | yes      | Redis connection string (shared with Rails API)      |
| `INTERNAL_JWT_SECRET`  | yes      | Must match the value set in the Rails API            |
| `SECRET_KEY_BASE`      | yes      | Phoenix secret key base (min 64 chars)               |
| `RAILS_API_URL`        | yes      | Internal URL of the Rails API (e.g. `http://api:3000`) |
| `PHX_HOST`             | yes      | Public hostname (e.g. `events.prostaff.gg`)          |
| `PORT`                 | no       | HTTP port (default: 4000)                            |
| `SCRAPER_API_KEY`      | no       | API key for Scraper → POST /events/notify            |

## Local Development

```bash
cp .env.example .env
# Edit .env with your values

mix deps.get
mix phx.server
# Listening on http://localhost:4000
```

Health check: `GET http://localhost:4000/health`

## WebSocket Connection (frontend)

```js
import { Socket } from "phoenix"

const socket = new Socket("wss://events.prostaff.gg/socket", {
  params: { token: "<user_jwt>" }
})
socket.connect()

// Notifications
const notifChannel = socket.channel(`notifications:${userId}`)
notifChannel.join()
notifChannel.on("notification.created", (payload) => { ... })

// Inhouse queue
const inhouseChannel = socket.channel(`inhouse:${orgId}`)
inhouseChannel.join()
inhouseChannel.on("queue_updated", (payload) => { ... })
inhouseChannel.on("check_in_expired", (payload) => { ... })
```

## Production Deploy (Coolify)

The service joins the shared `coolify` Docker network and is accessible from other services
by the container name Coolify assigns.

**Coolify panel env vars to set:**

```
REDIS_URL=redis://default:<password>@redis:6379/0
INTERNAL_JWT_SECRET=<same value as in Rails API>
SECRET_KEY_BASE=<64+ char random string>
RAILS_API_URL=http://api:3000
PHX_HOST=events.prostaff.gg
SCRAPER_API_KEY=<optional>
```

**Rails API Coolify panel — add these two:**

```
PHOENIX_EVENTS_ENABLED=true
PHOENIX_EVENTS_URL=http://<events-container-name>:4000
```

The container name is visible in Coolify under the deployed service. Typically matches the
service name in docker-compose (e.g. `events`), but verify in the Coolify dashboard.

## Domain Events Published by Rails

| Event type                       | Publisher                                |
|----------------------------------|------------------------------------------|
| `inhouse.session_started`        | InhouseQueuesController#start_session    |
| `scrim_request.accepted`         | ScrimRequestsController#accept           |
| `scrim_request.declined`         | ScrimRequestsController#decline          |
| `tournament_match.confirmed`     | MatchConfirmationService#confirm_match!  |
| `tournament_match.walkover`      | TournamentWalkoverJob                    |
| `team_goal.completed`            | TeamGoal#mark_as_completed!              |
| `team_goal.progress_updated`     | TeamGoal#update_progress!                |
| `player.transferred`             | Admin::PlayersController#transfer        |
| `roster.player_removed`          | RosterManagementService#remove_from_roster |
| `roster.player_hired`            | RosterManagementService#hire_from_scouting |

## Supervision Tree

```
ProstaffEvents.Supervisor
├── Registry (InhouseQueue.Registry)
├── Phoenix.PubSub
├── RedisSubscriber         — PSUBSCRIBE prostaff:events:*
├── InhouseQueue.Supervisor — DynamicSupervisor
├── InhouseQueue.Reconciler — fetches active queues from Rails on boot
└── ProstaffEventsWeb.Endpoint
```
