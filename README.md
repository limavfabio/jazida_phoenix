# Jazida Phoenix

Public, map-first explorer for ANM mining opportunities, with authenticated watches and change notifications. Official ANM publications remain authoritative; this application is an informational discovery layer.

## Local requirements

- Elixir/OTP versions from `.tool-versions` or `mise.toml`, when present
- PostgreSQL 16+ with PostGIS 3+
- GDAL 3+ with `ogr2ogr` on `PATH`
- Node/npm for the pinned MapLibre package under `assets/`

On Fedora, install the native services with `sudo dnf install postgresql-server postgis gdal`. On Debian/Ubuntu, use `postgresql postgresql-postgis gdal-bin` (package names can vary by PostgreSQL release).

The repository does not assume a `postgres` password. Unix-socket development is supported:

```sh
DATABASE_USER="$USER" DATABASE_PASSWORD= DATABASE_SOCKET_DIR=/var/run/postgresql mix setup
DATABASE_USER="$USER" DATABASE_PASSWORD= DATABASE_SOCKET_DIR=/var/run/postgresql mix phx.server
```

TCP connections use `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_USER`, `DATABASE_PASSWORD`, and `DATABASE_NAME`. Run `npm install --prefix assets` when the lockfile changes. The final local gate is:

```sh
DATABASE_USER="$USER" DATABASE_PASSWORD= DATABASE_SOCKET_DIR=/var/run/postgresql mix precommit
```

## Source synchronization

The scheduled Oban jobs and manual tasks call the same audited services:

```sh
mix jazida.sync.sople
mix jazida.sync.sigmine
```

SOPLE and SIGMINE run daily by default. Source URLs, download limits, and freshness thresholds live in application configuration and may be overridden with `SOPLE_STOCK_URL`, `SOPLE_ROUND_RESULTS_URL`, `SIGMINE_ACTIVE_URL`, `SIGMINE_INACTIVE_URL`, and `SOURCE_STALE_AFTER_HOURS`. The map's cached IBGE state-boundary overlay can be replaced with `STATES_GEOJSON_URL_TEMPLATE`; keep the `{state}` placeholder in that HTTPS URL.

Downloaded files can be checked against the current headers, status vocabulary, archive layout, required SIGMINE attributes, and EPSG:4674 projection without starting the application or writing to its database:

```sh
mix jazida.verify.sources \
  --stock /path/to/EstoqueAreas.csv \
  --rounds /path/to/ResultadoRodadaDisponibilidade.csv \
  --active /path/to/BRASIL.zip \
  --inactive /path/to/PROCESSOS_INATIVOS.zip
```

SIGMINE archives can exceed 1 GB after extraction. Give application temporary storage at least 6 GB for two archives, extracted shapefiles, and GDAL staging overhead.

## Production configuration

Production startup validates the settings it cannot safely infer:

- `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`
- `MAP_STYLE_URL` — HTTPS MapLibre style
- `RESEND_API_KEY` and `EMAIL_FROM`
- `ogr2ogr` available on `PATH`, and a PostgreSQL database where migrations may enable PostGIS

Swoosh uses its included Req API client and the Resend adapter. Secrets are never passed through shell command construction. See `docs/ANM_DATA_CONTRACT.md` for source assumptions and measured geometry coverage.
