# Fly.io deployment runbook

**Status:** planning artifact only. No Fly resources have been created and no
deployment configuration has been added to the application.

**Last verified:** 2026-07-18 against the repository, the installed `flyctl`,
and current Fly.io documentation.

## Recommendation

Launch VNI on one Phoenix Machine and one **unmanaged Postgres Flex 17** Machine
in `iad`. Give Postgres 512 MB RAM and a 10 GB volume, enable its WAL-based
backups at creation, and retain Fly's automatic volume snapshots. Use the
Postgres Flex image's bundled PostGIS extension.

This is the same architecture as Greg's existing `fara-tracker-db`, with two
deliberate differences:

- 512 MB for PostGIS rather than 256 MB; and
- WAL backups enabled from day one.

For the first launch, promote a reviewed logical dump of the local `vni_dev`
database. Do not rebuild production data by running all ingests inside the Fly
release. The current database is about 95 MB, while a clean rebuild needs GDAL,
ignored source caches, a Census API key, and manually acquired MEDSL files.
Those are data-pipeline concerns, not web-runtime concerns.

## Why unmanaged is acceptable here

VNI's launch dataset is public, mostly read-only, reproducible, and small. The
verified launch dump remains an independent recovery artifact. Losing the
database would cause an outage, but it would not destroy irreplaceable user
data.

That makes a single database Machine a rational launch trade:

- roughly $4/month for a 512 MB Machine in `iad`;
- $1.50/month for a 10 GB volume;
- snapshot storage is $0.08/GB-month, with the first 10 GB free each month;
- plus the Phoenix Machine, likely putting the initial stack around $9-12/month
  before meaningful traffic.

Recheck the calculator before provisioning:

- <https://fly.io/docs/about/pricing/>

Fly does not operate or support this database. We own upgrades, monitoring,
recovery, and any replica/failover work. Fly states that plainly:

- <https://fly.io/docs/postgres/managing/>
- <https://fly.io/docs/apps/app-availability/>

That caveat is acceptable for the public Atlas. It stops being acceptable
before VNI stores pledges, email addresses, or other user-originated data.

## Upgrade trigger

Move to Fly Managed Postgres before any of these become true:

- VNI accepts durable user writes;
- losing writes between backups would harm a person;
- a database outage cannot wait for Greg to restore a snapshot;
- traffic requires replicas or automatic failover;
- maintenance and recovery work costs more attention than the managed premium.

The migration path is ordinary `pg_dump`/`pg_restore`. Both sides are
PostgreSQL 17 with PostGIS, and the Phoenix application only needs a new
`DATABASE_URL`. Starting unmanaged does not trap the application there.

## Current readiness

The application is close, but it is not deployable as-is.

| Area | Current state | Work required before launch |
|---|---|---|
| Phoenix release | No `Dockerfile`, release overlay, or release migration module | Generate and review Phoenix release artifacts |
| Fly config | No `fly.toml` or `.dockerignore` | Add explicit app, service, deploy, VM, and health-check config |
| Database | PostgreSQL 17 + PostGIS locally | Create Postgres Flex 17, enable PostGIS, and attach it |
| Migrations | No release command | Run release migrations before each deploy |
| Oban | Uses the default Postgres notifier | No change; direct Postgres supports `LISTEN/NOTIFY` |
| Health | No dedicated endpoint | Add a cheap `/healthz` readiness route that checks the Repo |
| Data | Complete local data; source caches are ignored | Export, checksum, restore, and verify a first-launch dump |
| Mail | Swoosh is present but no production mail flow exists | No provider needed until the product sends mail |
| Domain | Not chosen in this document | Validate on `*.fly.dev`, then attach the production hostname |
| Recovery | No production target exists | Enable WAL backups, inspect snapshots, and run a restore drill |

Current local baseline, recorded only to make first-launch verification exact:

- database: 95 MB;
- 435 districts, 435 profiles, and 435 district scores;
- 50 current map versions;
- 1,250 state-cycle result rows, including all 50 states for 2024;
- 0 Oban jobs;
- PostGIS 3.5.3;
- compactness rank 1 is `fl-27`, and rank 429 is `hi-2`;
- four profiles have no incumbent, which is expected source data.

Re-record the baseline on the actual launch commit. In-flight data work may
properly change it.

## Decisions to make at launch

Do not provision anything until these values are explicit:

```text
VNI_FLY_ORG=<Fly organization slug>
VNI_FLY_APP=<globally unique Fly app name>
VNI_FLY_DB=<globally unique Fly Postgres app name>
VNI_HOST=<production hostname, or APP.fly.dev for the first pass>
```

Defaults unless there is evidence to change them:

- primary region: `iad`;
- database image: `flyio/postgres-flex:17`;
- database Machine: one `shared-cpu-1x`, 512 MB RAM;
- database volume: 10 GB;
- database backups: WAL backups plus automatic volume snapshots;
- app Machine: one `shared-cpu-1x`, start at 512 MB and scale to 1 GB if
  observed memory says so;
- no app volume;
- one always-running app Machine because Oban starts with the application;
- Fly-managed TLS.

The app and database stay in the same region.

## Phase 1: deployment-preparation change

Do this on a clean branch after the current UI and data work lands. This phase
changes the repository but creates no external resources.

### 1. Generate release scaffolding

```sh
mix phx.gen.release --docker
```

Review every generated file. Expected artifacts include a multi-stage
`Dockerfile`, `.dockerignore`, `lib/vni/release.ex`, and release scripts such as
`bin/server` and `bin/migrate`.

The runtime image contains the release and digested static assets. It does not
need GDAL or the ignored ingest caches.

### 2. Finish production runtime configuration

Keep the existing runtime contract for `DATABASE_URL`, `SECRET_KEY_BASE`,
`PHX_HOST`, `PORT`, `ECTO_IPV6`, and `DNS_CLUSTER_QUERY`.

Let `fly postgres attach` create a dedicated `vni` role and `vni` database.
Fly's unmanaged attachment makes that role a superuser by default. Accept that
for this single-purpose, private-network cluster: it keeps release migrations,
extension ownership, restores, and Oban on one coherent connection contract.
Do not reuse the cluster for another application.

This is an explicit launch-stage compromise, not a general database doctrine.
Before VNI stores sensitive or user-originated data, move to Managed Postgres
and a least-privileged runtime role.

Keep Oban's default Postgres notifier. Unlike Managed Postgres behind
PgBouncer Transaction mode, Postgres Flex gives the application a direct
connection and supports `LISTEN/NOTIFY`.

Use a stable `RELEASE_COOKIE` secret and configure `rel/env.sh.eex` for Fly's
IPv6 BEAM networking:

```sh
export ERL_AFLAGS="-proto_dist inet6_tcp"
export RELEASE_DISTRIBUTION="name"
export RELEASE_NODE="${FLY_APP_NAME}-${FLY_IMAGE_REF##*-}@${FLY_PRIVATE_IP}"
```

Reference:

- <https://fly.io/docs/elixir/the-basics/clustering/>

### 3. Add a real readiness check

Add `GET /healthz` outside LiveView. It executes a cheap query such as
`SELECT 1` and returns:

- 200 only when Phoenix and the Repo are ready;
- 503 when the Repo is unavailable;
- no build, environment, credential, or dependency detail.

Do not use `/`; the mostly static homepage can return 200 while every data page
is dead. Do not use `/atlas`; rendering the Atlas every 15 seconds is a strange
way to ask Postgres whether it exists.

### 4. Add and review `fly.toml`

```toml
app = "<VNI_FLY_APP>"
primary_region = "iad"

[build]

[deploy]
  release_command = "bin/migrate"
  release_command_timeout = "5m"

[env]
  ECTO_IPV6 = "true"
  ERL_AFLAGS = "-proto_dist inet6_tcp"
  DNS_CLUSTER_QUERY = "<VNI_FLY_APP>.internal"
  PHX_HOST = "<VNI_HOST>"
  PHX_SERVER = "true"
  PORT = "4000"
  POOL_SIZE = "8"

[http_service]
  internal_port = 4000
  force_https = true
  auto_start_machines = true
  auto_stop_machines = "stop"
  min_machines_running = 1

  [http_service.concurrency]
    type = "requests"
    soft_limit = 200

  [[http_service.checks]]
    grace_period = "15s"
    interval = "15s"
    method = "GET"
    path = "/healthz"
    timeout = "2s"

[[vm]]
  size = "shared-cpu-1x"
  memory = "512mb"
```

References:

- <https://fly.io/docs/reference/configuration/>
- <https://fly.io/docs/reference/health-checks/>

### 5. Verify the deployable artifact locally

```sh
mix precommit
MIX_ENV=prod mix assets.deploy
docker build --tag vni:release-candidate .
```

Boot the container against a disposable Postgres 17 + PostGIS database. Run
its release migration command and request `/healthz`, `/`, `/atlas`, one
district page, and one state page.

## Phase 2: provision Fly resources

Everything in this phase creates billable external state. Stop and get an
explicit go-ahead before running it.

### 1. Confirm identity and names

```sh
fly auth whoami
fly orgs list
fly apps list
fly postgres list
```

Confirm the target is Greg's personal organization and both names are unused.

### 2. Create the application without deploying

```sh
fly apps create "$VNI_FLY_APP" --org "$VNI_FLY_ORG"
```

### 3. Create unmanaged Postgres Flex

```sh
fly postgres create \
  --name "$VNI_FLY_DB" \
  --org "$VNI_FLY_ORG" \
  --region iad \
  --image-ref flyio/postgres-flex:17 \
  --initial-cluster-size 1 \
  --vm-size shared-cpu-1x \
  --vm-memory 512 \
  --volume-size 10 \
  --enable-backups
```

Do not add `--autostart`. The database must remain running; it cannot safely
scale to zero like a stateless web Machine.

Capture the generated `postgres` password once in the password manager. Never
put it in Git, the runbook, shell history, or logs.

Verify the actual image, Machine, volume, and cluster health:

```sh
fly status --app "$VNI_FLY_DB"
fly image show --app "$VNI_FLY_DB"
fly scale show --app "$VNI_FLY_DB"
fly volumes list --app "$VNI_FLY_DB"
fly postgres config show --app "$VNI_FLY_DB"
```

### 4. Attach with a dedicated application role

```sh
fly postgres attach "$VNI_FLY_DB" \
  --app "$VNI_FLY_APP" \
  --database-name vni \
  --database-user vni \
  --superuser \
  --variable-name DATABASE_URL
```

This creates the dedicated `vni` database and role and sets `DATABASE_URL` on
the Phoenix app. The role is a superuser because this is a single-purpose
unmanaged cluster and must own restored objects, migrations, and extensions.
Never use the raw `postgres` connection URL as the app secret.

Set these other app secrets:

- `SECRET_KEY_BASE` — newly generated for production;
- `RELEASE_COOKIE` — one stable, production-only BEAM cookie.

Verify names only:

```sh
fly secrets list --app "$VNI_FLY_APP"
```

Do not set `CENSUS_API_KEY` on the web app. The runtime does not need it.

### 5. Prove PostGIS before proceeding

Connect as the cluster administrator to the application database:

```sh
fly postgres connect --app "$VNI_FLY_DB" --database vni
```

Run:

```sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS citext;
SELECT version();
SELECT postgis_full_version();
```

If either extension fails, stop. Do not deploy VNI against a merely-Postgres
database and hope geometry becomes philosophical.

### 6. Prove both backup layers

```sh
fly postgres backup config show --app "$VNI_FLY_DB"
fly postgres backup list --app "$VNI_FLY_DB"
fly volumes list --app "$VNI_FLY_DB"
fly volumes snapshots list <VOLUME_ID>
```

Fly takes daily volume snapshots and retains them for five days by default.
WAL backups provide the second recovery path and can restore into a new
Postgres cluster.

References:

- <https://fly.io/docs/postgres/managing/backup-and-restore/>
- <https://fly.io/docs/flyctl/postgres-backup/>

## Phase 3: promote the first production dataset

Do this before the first web deploy so a successful release cannot boot
against an empty Atlas.

### 1. Freeze and audit the source snapshot

Start from the exact Git commit intended for launch. Run the full test suite
and data verification checks. Confirm that the local database contains no
test, account, private, or unrelated data.

Record a manifest beside the dump containing:

- Git SHA and UTC timestamp;
- PostgreSQL and PostGIS versions;
- methodology version;
- baseline row counts and rank extrema;
- source database size;
- dump SHA-256.

The dump and manifest are release artifacts. They do not belong in Git.

### 2. Produce the dump

```sh
pg_dump \
  --format=custom \
  --no-owner \
  --no-acl \
  --exclude-table-data=public.oban_jobs \
  --file=/tmp/vni-first-launch.dump \
  "$LOCAL_DATABASE_URL"

shasum -a 256 /tmp/vni-first-launch.dump
```

### 3. Restore over Fly's private proxy

In terminal one:

```sh
fly proxy 15432:5432 --app "$VNI_FLY_DB"
```

In terminal two, restore as the cluster administrator. Use `-W` so the
password is prompted rather than written into shell history:

```sh
pg_restore \
  --exit-on-error \
  --no-owner \
  --no-acl \
  --host=127.0.0.1 \
  --port=15432 \
  --username=postgres \
  --dbname=vni \
  -W \
  /tmp/vni-first-launch.dump
```

This is safe only against the new, empty `vni` database. If the target is not
empty, stop. Do not add `--clean` casually.

### 4. Verify the restored database

Verify extensions, migration count, table counts, no active Oban jobs, and the
known extrema. Run `ANALYZE` after restore.

Reject a mismatched snapshot. Fix the source database or pipeline, make a new
dump, and restore again; do not patch production with individual ingests.

## Phase 4: first deploy

```sh
fly config validate --strict --app "$VNI_FLY_APP"
fly deploy --ha=false --app "$VNI_FLY_APP"
```

`--ha=false` keeps the intended starting shape at one application Machine.
Confirm with `fly scale show --app "$VNI_FLY_APP"`.

The deploy must build the image, migrate through `DATABASE_URL`, start Phoenix
on port 4000, and pass `/healthz`. If the release command fails, stop. Do not
use `--skip-release-command` to wallpaper over it.

## Phase 5: acceptance on `fly.dev`

```sh
fly status --app "$VNI_FLY_APP"
fly checks list --app "$VNI_FLY_APP"
fly logs --app "$VNI_FLY_APP"
fly status --app "$VNI_FLY_DB"
```

Acceptance checklist:

- `/healthz` returns 200;
- `/`, `/atlas`, `/districts`, `/states`, `/methodology`, `/sources`, and
  `/act` load over HTTPS;
- one district and one state detail page render their data;
- LiveView connects over WebSocket;
- Atlas shapes and sort controls work;
- rank extrema match the launch manifest;
- app and database logs have no connection, memory, PostGIS, Oban, or asset
  errors;
- the app and database Machines remain running after an idle period;
- restarting the Phoenix Machine leaves the site healthy and data unchanged;
- no development routes, Tidewave endpoint, mailbox, or LiveDashboard are
  public.

Take desktop and mobile screenshots from the deployed URL. Watch both Machine
memory graphs during the acceptance pass. Scale either Machine to 1 GB if it
shows sustained pressure or any OOM behavior; memory is cheaper than folklore.

## Phase 6: attach the production domain

Set the final `PHX_HOST`, deploy it, then:

```sh
fly certs add "$VNI_HOST" --app "$VNI_FLY_APP"
fly certs setup "$VNI_HOST" --app "$VNI_FLY_APP"
fly certs check "$VNI_HOST" --app "$VNI_FLY_APP"
```

Apply the exact DNS records Fly returns. Prefer A/AAAA records for an apex and
CNAME for a subdomain.

- <https://fly.io/docs/networking/custom-domain/>

## Routine deploy procedure

For every release:

1. identify the exact Git SHA and ensure the worktree is clean;
2. run `mix precommit`;
3. review migrations for compatibility with the running release;
4. run `fly deploy` and read the release-command output;
5. check app and database status, checks, logs, and memory;
6. smoke-test `/healthz`, one data-heavy page, and the changed flow;
7. record the deployed SHA.

Use expand/contract migrations. Data refreshes are separate releases with
their own source manifest, verification results, and logical dump.

## Recovery procedure

There is no automatic failover. If the database Machine or volume fails:

1. stop deployment and data-refresh work;
2. identify the newest valid WAL backup and volume snapshot;
3. restore into a **new** Postgres app using the same Postgres image and a
   volume at least as large as the source;
4. verify extensions, schema, counts, extrema, and application behavior;
5. attach the Phoenix app to the verified replacement database;
6. retain the failed database until recovery is accepted.

Fly's snapshot recovery contract requires restoring into a new Postgres app:

- <https://fly.io/docs/postgres/managing/backup-and-restore/>

Run one recovery drill before attaching the production domain. A backup that
has never been restored is a rumor with a timestamp.

Keep an encrypted logical dump outside Fly as a third recovery path. Once VNI
accepts user writes, stop here and move to Managed Postgres before launch of
that feature.

## Stop conditions

Abort rather than working around any of these:

- the database image is not PostgreSQL 17;
- PostGIS or `citext` cannot be enabled;
- the app runtime uses the raw `postgres` role instead of its dedicated `vni`
  role;
- WAL backup configuration or volume snapshots cannot be verified;
- restored counts or the methodology manifest do not match;
- `/healthz` passes while data pages cannot query Postgres;
- either Machine OOMs during acceptance;
- a secret appears in Git, logs, terminal output, or this document;
- acceptance requires skipping migrations or disabling health checks;
- the only recovery plan is to repair the sole production database in place.
