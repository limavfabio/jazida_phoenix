# Jazida Phoenix MVP implementation plan

## Objective

Build and verify a production-shaped Portuguese-language web application that helps Brazilian mining professionals discover areas in the ANM availability pipeline, inspect their official status and geometry, watch individual processes, and receive a daily email when a material official status changes.

The application is an information and monitoring product. It is not an ANM transaction client, a legal opinion, or a prediction engine.

## Definition of done

The MVP is complete only when all of the following are true:

- Official SOPLE stock and round-result files can be imported repeatedly and idempotently.
- Relevant active and inactive SIGMINE polygons are joined to SOPLE records by normalized mining-process number.
- A failed or partial import never replaces the last successful visible dataset.
- Each successful import records its source, timestamps, checksum, row counts, warnings, and outcome.
- Material changes are stored once and can be traced back to the import that observed them.
- An anonymous user can search and filter the nationwide opportunity catalog, navigate the map, open an area, and see source/freshness information.
- A registered user can watch and unwatch an individual mining process.
- A material change to a watched process produces one notification and at most one inclusion in the user's daily digest.
- The UI clearly distinguishes raw ANM labels from the application's broader display categories.
- Stale or failed source synchronization is visible to users; the UI never silently presents stale data as current.
- No confidential auction information is inferred or collected, and unnecessary holder/winner personal data is not stored.
- Automated tests cover the domain contracts, persistence, import atomicity, spatial queries, permissions, notification deduplication, and relevant LiveView behavior.
- A real-source acceptance import, browser smoke test, and performance review have been completed and documented.
- `mix precommit` passes with no warnings or failures.

## Authoritative inputs

Use the supplied edital for procedural/legal language and official machine-readable ANM datasets for application data.

- Local edital: `docs/Edital 8ª Rodada 2.pdf`
- SOPLE data: <https://dadosabertos.anm.gov.br/SOPLE/>
- SIGMINE data: <https://dadosabertos.anm.gov.br/SIGMINE/PROCESSOS_MINERARIOS/>
- Cadastro Mineiro microdata, reserved for later enrichment: <https://dadosabertos.anm.gov.br/SCM/microdados/>
- Official SOPLE description: <https://www.gov.br/anm/pt-br/assuntos/acesso-a-sistemas/sistema-de-oferta-publica-e-leilao-de-areas-sople/sistema-de-oferta-publica-e-leilaode-areas-SOPLE/>

`docs/Public Offer and Auction Schedule.pdf` is research material containing a saved AI conversation. It is not an authoritative source and must not override the edital or official ANM datasets.

Important source contracts already established:

- `EstoqueAreas.csv` is semicolon-delimited UTF-8 with a possible BOM, quoted fields, and Brazilian decimal commas.
- SOPLE stock is updated daily. Other SOPLE resources update after homologation/adjudication for ongoing rounds and monthly for concluded rounds.
- SIGMINE publishes zipped shapefiles for active and inactive processes daily.
- SIGMINE source geometry is SIRGAS 2000 (`EPSG:4674`), not WGS84.
- SIGMINE and Cadastro Mineiro can be joined through the mining process identifier/`DSProcesso`, after normalization.
- Upstream status strings are an external contract and may acquire new values.

## Product assumptions

- Initial users are independent geologists, mining consultants, and small mining operators in Brazil.
- The product language is Brazilian Portuguese.
- The primary viewport is desktop, but core discovery and monitoring workflows must be responsive and accessible on mobile.
- The initial differentiator is trustworthy monitoring and provenance, not map rendering by itself.
- Opportunity discovery is based on explicit official states such as `Para Análise`, `Em Análise`, `Apta para Disponibilidade`, edital/auction states, and `Livre`.
- “Near caducity” predictions remain out of scope until a mining-domain specialist approves a deterministic rule set and its source fields.
- A basemap provider and production email adapter may remain configurable until deployment, but the application must have working development/test adapters and clear production configuration errors.

## Verified local database baseline

Verified on 2026-07-29 before MVP implementation:

- The workstation PostgreSQL 18.3 server is reachable through `/var/run/postgresql` using peer authentication as database user `limavfabio`.
- The workstation has PostGIS 3.6.4 and GDAL 3.12.4 installed. `ogr2ogr` is available at `/usr/bin/ogr2ogr`.
- PostGIS was loaded and queried successfully in a temporary PostgreSQL 18 database, then that verification database was removed.
- Development and test configuration accepts `DATABASE_USER`, `DATABASE_PASSWORD`, `DATABASE_NAME`, `DATABASE_HOST`, `DATABASE_PORT`, and `DATABASE_SOCKET_DIR` while retaining the generated `postgres`/TCP defaults.
- `mix precommit` passes against the workstation server with 5 tests and no failures:

      DATABASE_USER=limavfabio \
        DATABASE_PASSWORD= \
        DATABASE_SOCKET_DIR=/var/run/postgresql \
        mix precommit

The implementation goal should use this native PostgreSQL/PostGIS instance for migrations, spatial tests, real-source imports, and browser acceptance. The required native packages are reproducible with `sudo dnf install postgis gdal`; `unzip` is already installed.

## MVP scope

### Included

- Nationwide opportunity map and list.
- Search by normalized or formatted mining-process number.
- Filters for display category, raw official status, state, municipality, substance, availability regime, and round.
- Area detail view with process number, geometry, hectares, substances, regime, official statuses, last official event where available, round history, source links, and freshness.
- Structured round/event support, initially populated for the supplied 8th-round edital.
- User registration, login, logout, email confirmation/reset flows provided by Phoenix authentication conventions.
- Watch and unwatch individual processes.
- In-app notification history.
- Deduplicated daily email digest for material watched-process changes.
- Import health/freshness state suitable for user-facing banners and operator diagnostics.
- Portuguese UI copy, loading states, empty states, error states, responsive behavior, and basic accessibility.

### Excluded

- Bidding, financial proposals, payments, title applications, or any authenticated action against SOPLE.
- GOV.BR, e-CPF, or e-CNPJ integration.
- Legal/mineral viability recommendations or guarantees of availability.
- Predictive caducity scoring.
- Automated edital/DOU PDF parsing, OCR, or LLM extraction.
- Environmental, indigenous-land, municipal-zoning, or other third-party overlays.
- Radius/polygon subscriptions, WhatsApp, SMS, browser push, native mobile applications, reports, billing, or subscription tiers.
- A general map of every active mining title unrelated to the availability pipeline.
- Storing or displaying winner/holder names and masked CPF/CNPJ values unless a later approved product requirement needs them.

## Architecture decisions

### Application

- Keep the application as one Phoenix 1.8 release and one PostgreSQL database.
- Use LiveView for the application shell, filters, search, details, watchlists, and account workflows.
- Use a small JSON endpoint for selected-area details only where the map hook needs it.
- Use a dedicated tile controller backed directly by PostGIS `ST_AsMVT`; do not add a separate tile server.
- Use an external JavaScript LiveView hook for MapLibre. The hook owns its map DOM and must use a unique ID plus `phx-update="ignore"`.
- Keep all custom JavaScript in `assets/js` and import dependencies into `app.js`.
- Remove the scaffold's DaisyUI dependency and Tailwind plugins. Build the interface with Tailwind classes and small raw CSS rules, without `@apply`.

### Data and geometry

- Enable PostGIS through a generated Ecto migration.
- Store canonical geometry as `geometry(MultiPolygon, 4674)` with a GiST index.
- Transform geometry to Web Mercator (`EPSG:3857`) only for vector-tile generation.
- Preserve upstream raw values. Derive display categories in domain code and store the derived category only if necessary for indexed queries.
- Use strings for upstream-controlled statuses rather than `Ecto.Enum`, so a new official value cannot make an import invalid.
- Use PostgreSQL text arrays for the MVP's substances, uses, and municipalities; normalize only when a demonstrated query or integrity requirement earns additional tables.

### Ingestion

- Use `Req` for downloads.
- Use `NimbleCSV` for SOPLE parsing.
- Use GDAL's `ogr2ogr` as a declared system/container dependency for shapefile inspection, validation, and loading. Do not implement a shapefile parser.
- Use Oban for scheduled imports, retries, and notification delivery.
- Download to a unique temporary directory, validate the response and archive, calculate SHA-256, then import through staging tables.
- Import SOPLE before geometry so the relevant process universe is known.
- Load active and inactive SIGMINE shapefiles into staging, normalize their identifiers, upsert only processes in the availability/round universe, and truncate/drop staging data after a successful transaction.
- Never construct shell arguments from user input. Source URLs, filenames, and GDAL options are application-controlled.
- If a source is unchanged by checksum, finish successfully without creating changes or notifications.

### Map delivery

- Use MapLibre GL JS with a style URL supplied through runtime configuration.
- Serve vector tiles from `/api/tiles/areas/:z/:x/:y.mvt`.
- At low zooms, return lightweight centroids or aggregated counts; at useful inspection zooms, return clipped/simplified polygons.
- Keep tile properties small: internal ID, process number, display category, state, area, regime, and primary substance.
- Fetch full details only after selection.
- Keep status/category filtering client-side when properties are already present in tiles. Add server-side tile filters only when measured tile size or query performance requires them.

### Notifications

- Watch records target a stable mining-process record, not a current status row.
- Define a material-change allowlist. At minimum it includes changes to stock status, latest edital status, availability regime, round situation, and geometry withdrawal/replacement.
- Do not notify about changes that only affect source observation timestamps or formatting.
- Give each change a deterministic fingerprint and enforce a unique database constraint.
- Give each user/change notification a unique constraint.
- Build one digest per user and calendar day in the configured Brasília timezone.
- Mark delivery only after the mail adapter accepts the message; retries must reuse the same notification/digest identity.

## Proposed data model

Use generated migrations with underscore names and refine them before migrating.

### `mining_processes`

- `id`
- `process_number` — canonical `NNNNNN/YYYY`, unique
- `number`
- `year`
- `state_code`
- `municipalities` — text array
- `area_ha` — decimal
- `phase`
- `last_event`
- `substances` — text array
- `substance_uses` — text array
- `geometry` — `MultiPolygon`, SRID 4674
- `geometry_source_observed_at`
- timestamps

Indexes: unique process number, state, GIN arrays where query plans justify them, and GiST geometry.

### `area_availability`

- `mining_process_id`, unique foreign key
- `availability_regime`
- `stock_status_raw`
- `latest_edital_status_raw`
- `display_category`
- `nominated`
- `listed_in_edital`
- `source_observed_at`
- `material_fingerprint`
- timestamps

### `rounds`, `round_events`, and `round_areas`

- Round number/title, official identifiers, edital/source URL, status, and timezone.
- Structured event name, starts/ends timestamps, official raw label, and source reference.
- Process, area number, modality, regime, raw situation, winning bid when public and relevant, and observation time.
- Do not import winner identity fields in the MVP.

### `source_imports`

- Source name and URL.
- Status: running, succeeded, failed, or unchanged.
- Started/finished timestamps.
- Source modification metadata, SHA-256, byte size, parsed/imported/skipped row counts, warning count, and sanitized error summary.
- Ensure only a successful import advances the application's source-freshness marker.

### `process_changes`

- Mining process, source import, changed field/category, old and new values, observed timestamp, and deterministic fingerprint.
- Store structured JSON values without copying unrelated source fields.

### Accounts and monitoring

- Phoenix-generated users/tokens tables.
- `watches`: user, mining process, active flag/timestamps, unique active relationship.
- `notifications`: user, process change, delivery state, read timestamp, and unique user/change relationship.
- `digests`: user, Brasília calendar date, delivery state, sent timestamp, and unique user/date relationship.

## Implementation sequence

Complete each slice and its gate before expanding scope. Update the checkboxes in this file as work is completed.

### Slice 0 — Baseline and data-contract spike

- [x] Make development/test database connectivity configurable through `DATABASE_USER`, `DATABASE_PASSWORD`, `DATABASE_NAME`, `DATABASE_HOST`, `DATABASE_PORT`, and `DATABASE_SOCKET_DIR`, while retaining the generated TCP defaults.
- [x] Run the existing test suite and `mix precommit`; record pre-existing failures without masking them.
- [x] Confirm PostgreSQL/PostGIS availability in development and test.
- [x] Inspect current official SOPLE headers/status values and SIGMINE archive/projection metadata.
- [x] Build representative source fixtures under `test/support/fixtures/anm/`; do not commit entire official datasets.
- [x] Prove normalization joins formatted `DSProcesso` values to SOPLE process numbers.
- [x] Measure geometry coverage for current SOPLE opportunity and round records using a one-off, non-production spike.
- [x] Review the proposed display-category mapping against every distinct current raw status.
- [x] Record unknown statuses and missing geometry as first-class warnings.
- [x] Prove PostGIS can generate a non-empty MVT tile from representative imported geometry.

Gate:

- Join/geometry coverage is at least 99%, or every shortfall is explained and accepted in this document.
- No status is silently assigned to a misleading fallback category.
- The source files can be processed within reasonable local memory and disk bounds.

### Slice 1 — Project foundation

- [x] Add only the dependencies earned by the architecture: `geo_postgis`, `nimble_csv`, `oban`, and MapLibre GL JS.
- [x] Declare/document GDAL for local and deployment environments; add reproducible container setup if the project has no existing deployment convention.
- [x] Remove DaisyUI from `mix.exs` and `assets/css/app.css`; replace scaffold usages before removal.
- [x] Preserve the Phoenix/Tailwind v4 import syntax required by `AGENTS.md`.
- [x] Configure Oban queues/plugins for import and notification work.
- [x] Configure map style URL, source URLs, freshness thresholds, and Brasília timezone through application/runtime configuration.
- [x] Add clear runtime validation for production-only map/email settings without breaking tests.
- [x] Generate the PostGIS and initial catalog migrations using `mix ecto.gen.migration`.

Gate:

- The project compiles with warnings as errors.
- Development and test databases migrate from empty successfully.
- Existing tests remain green.

### Slice 2 — Mining catalog and import audit trail

- [x] Implement one module per file under `lib/jazida_phoenix/mining/` and a narrow public `JazidaPhoenix.Mining` context.
- [x] Implement process-number normalization without creating atoms from source/user data.
- [x] Implement schemas and changesets for processes, availability, rounds, round events, round areas, imports, and changes.
- [x] Add database constraints for stable identities, fingerprints, and valid associations.
- [x] Implement display-category mapping while preserving raw labels.
- [x] Add query APIs for search, filters, selected-area detail, and viewport/tile lookup.
- [x] Add tests for contracts, constraints, filtering, source freshness, and spatial queries.

Gate:

- Domain tests demonstrate invalid/duplicate states are rejected by constraints.
- Unknown official statuses remain importable, visible, and warned about.

### Slice 3 — SOPLE ingestion

- [x] Implement a reusable downloader with bounded timeouts, redirects, response validation, streaming to a unique temp directory, and SHA-256 calculation.
- [x] Implement CSV parsers for stock and round results with fixtures covering BOMs, accents, quoted semicolons, blank values, and Brazilian decimal commas.
- [x] Import through staging and a transaction.
- [x] Upsert current records without deleting historical round records.
- [x] Generate material `process_changes` by comparing fingerprints/fields inside the successful import transaction.
- [x] Record unchanged, successful, warning, and failed import outcomes.
- [x] Add an idempotent manual Mix task for SOPLE synchronization.
- [x] Add an Oban worker that invokes the same application service rather than duplicating import logic.
- [x] Add tests for unchanged reruns, upstream additions, updates, removals, malformed rows, download failures, retry safety, and transaction rollback.

Gate:

- The same fixture imported twice creates no duplicate domain records or changes.
- A malformed replacement leaves the previous successful catalog and freshness marker intact.

### Slice 4 — SIGMINE geometry ingestion

- [x] Implement archive validation and safe extraction that rejects path traversal and unexpected file layouts.
- [x] Invoke GDAL with fixed application-owned arguments to validate SRID, geometry type, and source attributes.
- [x] Load active and inactive data into isolated staging tables.
- [x] Normalize `PROCESSO`/`DSProcesso`, repair only safely repairable geometry, coerce polygons to multipolygons, and preserve SRID 4674.
- [x] Upsert only geometry relevant to SOPLE stock or historical round areas.
- [x] Record missing, duplicate, invalid, or ambiguous geometries as warnings with counts and process identifiers suitable for diagnostics.
- [x] Treat material geometry addition, replacement, or withdrawal as a process change.
- [x] Add a manual Mix task and Oban worker sharing the same application service.
- [x] Add spatial import, idempotency, rollback, and unsafe-archive tests.

Gate:

- Fixture geometry coverage is 100%.
- Real-source coverage meets the Slice 0 threshold.
- Every stored geometry is valid, non-empty, SRID 4674, and spatially indexed.

### Slice 5 — Vector tiles and read APIs

- [x] Add a tile route/controller with validated integer `z/x/y` parameters and appropriate zoom bounds.
- [x] Generate MVT using `ST_TileEnvelope`, indexed bounding-box predicates, `ST_Transform`, and `ST_AsMVTGeom`/`ST_AsMVT`.
- [x] Return low-zoom aggregations/centroids and higher-zoom polygons with measured thresholds.
- [x] Add immutable or short-lived cache headers appropriate to the current import version.
- [x] Add a selected-area JSON endpoint only if the map hook cannot use LiveView cleanly for selection.
- [x] Ensure endpoints expose no account or unnecessary personal data.
- [x] Add controller tests for valid tiles, empty tiles, invalid coordinates, content type, and area authorization/data boundaries.
- [x] Capture representative `EXPLAIN (ANALYZE, BUFFERS)` plans and remove sequential spatial scans from normal tile/detail paths.

Gate:

- A nationwide initial map view has bounded payload size.
- Representative warm tile requests complete within 500 ms locally and typical detail/search queries within 300 ms on the acceptance dataset.

### Slice 6 — Public explorer UI

- [x] Replace the scaffold controller homepage with an `ExplorerLive` route in the correct browser/live session.
- [x] Begin the template with `<Layouts.app flash={@flash} current_scope={@current_scope}>` as applicable.
- [x] Build a polished, responsive application shell, search, filter controls, category legend, map, selected-area drawer, loading states, empty states, errors, and freshness banner.
- [x] Add stable unique DOM IDs for all key elements and controls.
- [x] Add the external MapLibre hook under `assets/js/`, register it in `app.js`, and use a unique hook ID plus `phx-update="ignore"`.
- [x] Keep filters and selected process shareable in the URL where practical.
- [x] Show raw official status alongside plain-language explanation and source timestamp.
- [x] Link to official ANM process/SOPLE pages and display the informational/legal disclaimer.
- [x] Use `<.icon>`, `<.input>`, `<.form>`, and LiveView navigation conventions from `AGENTS.md`.
- [x] Add focused LiveView tests using IDs/selectors rather than raw HTML or fragile copy.

Gate:

- Anonymous users can complete search, filter, map selection, detail, and source-navigation flows on desktop and mobile.
- Keyboard focus, labels, contrast, and reduced-motion behavior pass a manual accessibility review.

### Slice 7 — Accounts, watches, and notifications

- [x] Generate authentication using the Phoenix 1.8 auth generator and keep authenticated routes in the correct `live_session` with `current_scope`.
- [x] Add watch, notification, and digest migrations/schemas with uniqueness constraints.
- [x] Add watch/unwatch controls to the detail view with sign-in routing for anonymous users.
- [x] Authorize every watch and notification query through the current user scope.
- [x] Translate material process changes into deduplicated user notifications after the source import commits.
- [x] Build an in-app notification list/read flow using LiveView streams.
- [x] Build a daily digest Oban worker and Portuguese email with official-source links, freshness, and unsubscribe/settings link.
- [x] Use the existing Swoosh local adapter for development and Req-compatible production configuration.
- [x] Add permissions, deduplication, retry, digest-boundary, and email-content outcome tests.

Gate:

- One source change creates one notification per watching user, even across retries.
- Users cannot read, modify, or infer another user's watches or notifications.
- One user receives no more than one digest for a Brasília calendar date.

### Slice 8 — Operations, hardening, and acceptance

- [x] Schedule source jobs according to official cadence without overlapping the same source import.
- [x] Add telemetry/log metadata for source, import ID, duration, row counts, warnings, and outcome without logging personal data or full source rows.
- [x] Add a health/readiness check that distinguishes application health from data freshness.
- [x] Add user-facing stale thresholds and operator-visible failure summaries.
- [x] Apply rate/size bounds to public search/detail/tile endpoints where necessary, preferring existing framework facilities over a new dependency.
- [x] Review temporary-file cleanup, zip-bomb limits, SQL parameterization, shell argument safety, email abuse paths, and secret handling.
- [x] Run a full real-source synchronization from an empty database and record source timestamps, checksums, row counts, geometry coverage, warnings, duration, and peak resource observations in the completion notes below.
- [x] Run the complete automated test suite.
- [x] Run `mix precommit` and fix every failure.
- [x] Start the application and perform browser smoke tests for anonymous discovery, authentication, watch creation, a simulated import change, in-app notification, digest preview, mobile layout, and stale-data behavior.
- [x] Review the final diff for scope, dead code, accidental source files, secrets, generated artifacts, and unrelated changes.

Gate:

- Every item in the Definition of Done is evidenced by an automated test, recorded acceptance run, or explicit manual verification note.
- No known correctness, permission, data-loss, or misleading-status defect remains open.

## Test strategy

### Unit and contract tests

- Process-number normalization and round-trip formatting.
- Decimal/date/text normalization.
- Raw-status display-category mapping, including unknown values.
- Material-change classification and deterministic fingerprints.
- Digest timezone/date boundary behavior.

### Persistence and integration tests

- Foreign keys, uniqueness, and spatial validity constraints.
- Idempotent staging/upsert behavior.
- Transaction rollback on parse, geometry, or database failure.
- Source freshness advances only on successful import.
- Change and notification deduplication under retry/concurrency.
- GiST-backed bounding-box/tile queries.

### Web and permission tests

- Explorer mount, stable IDs, search/filter/detail outcomes, empty states, stale states, and invalid parameters.
- Authenticated route/session behavior and `current_scope` propagation.
- Watch and notification ownership isolation.
- Tile and detail endpoints disclose only intended public fields.
- Forms use `to_form` and are exercised with LiveView form helpers.

### Acceptance tests

- Fixture-driven CI tests never depend on ANM network availability.
- A separate explicit source-verification Mix task checks current headers, expected resources, projection, and status vocabulary without mutating production data.
- A real-source acceptance import is required before declaring the MVP complete.
- Browser smoke testing is required after the final build; automated LiveView tests do not replace visual/map verification.

## Required implementation discipline

- Follow `AGENTS.md` and the existing Phoenix architecture.
- Keep contexts and modules narrow; do not create generic repository/service layers.
- Never nest multiple Elixir modules in one file.
- Generate migrations with `mix ecto.gen.migration` and review them before running.
- Preserve unrelated user changes in a dirty worktree.
- Do not add dependencies for functionality already supplied conventionally by Phoenix, PostgreSQL/PostGIS, Req, Swoosh, GDAL, or the standard library.
- Do not scrape interactive SOPLE/Cadastro pages while official machine-readable data satisfies the requirement.
- Do not silently broaden scope when a source limitation appears. Record the limitation and implement the smallest truthful behavior.
- Do not mark the goal complete merely because tests pass; complete the real-source and browser acceptance gates.

## Product/operational decisions that may require user input

These should not block fixture-backed implementation. Ask only when the decision becomes necessary for production acceptance:

- Production basemap provider/style URL and allowed usage volume.
- Production email provider, sender domain, and credentials.
- Deployment target and its PostgreSQL/PostGIS/GDAL support.
- Final public product name and branding clearance.
- Domain-expert acceptance of the display-category terminology and legal disclaimer.

If credentials are unavailable, finish and verify the adapter boundary with local/test adapters, document the exact production-only blocker, and do not claim production delivery is complete.

## Completion notes

Fill this section during implementation; do not remove failed-attempt evidence that affects confidence.

- Final commit/worktree summary: one Phoenix 1.8 application with PostGIS catalog/imports, PostGIS MVT delivery, LiveView explorer, generated authentication, scoped watches/notifications/digests, audited Oban operations, health/readiness endpoints, official-source contract task, local PostGIS Compose service, and operator documentation. No complete official dataset or generated acceptance artifact is committed.
- Automated verification commands and results: `mix compile --warnings-as-errors`, `mix assets.build`, 140 ExUnit tests, `git diff --check`, a source-contract verification of all four official files, a clean-database migration rehearsal, database invariants, spatial query plans, and browser acceptance passed. The rehearsal enabled PostGIS 3.6.4 and created eight structured 8th-round events from the supplied edital.
- Real-source import date and source timestamps: acceptance database rebuilt and imported 2026-07-30 03:47:10–03:53:00 UTC from the 2026-07-29 downloaded snapshot, then reconciled to the stock published at 2026-07-30 04:01:20 UTC. Current upstream `Last-Modified` values are 2026-07-30 04:01:20 UTC (stock), 2026-07-01 05:02:23 UTC (round results), 2026-07-29 02:52:10 UTC (active SIGMINE), and 2026-07-29 03:10:05 UTC (inactive SIGMINE). Current stock SHA-256 is `b5890f18f1601e4feaa930c488ed182010d5b811d6cee80f82b298e003216336`; initial clean-run stock snapshot SHA-256 was `1a3088185e7418296e90fbf4f98cf6fd6bd3b7b1cff104f56407571fc200ee91`; round-results SHA-256 is `2bd662cb60dc97eba6289064b43e3ff89d90402728c55430b57e3e771c5d38d1`; combined SIGMINE audit SHA-256 is `840bd06a2f63a6af518ae055f1c4b6020d81bec5c9ad8efc34c87104afcbc2bf` (active archive `07909e08d04ece067c500af60078881748030a430340f1b300c50eb314810380`, inactive archive `1647003c5d8215d49c691e9c9ade095dc3cb789ea5d629b6e01e73059a2ec645`). Scheduled downloads preserve valid upstream HTTP timestamps and otherwise fall back explicitly to fetch time.
- SOPLE rows parsed/imported/skipped: current stock 147,663/147,609/54, with 57 warnings (54 invalid identifiers, including `000000/2026` and sanitized security-test payloads, plus three invalid areas). The final catalog has 147,614 unique positive process numbers and zero process number `0`.
- Historical round rows imported: 31,841/31,841/0 with zero warnings. Round 8 includes official process `48051.007646/2023-43` and eight structured edital schedule events; winner identity fields were intentionally not retained.
- SIGMINE relevant processes and geometry coverage: 933,284 source features parsed; 147,522 relevant processes received geometry, 92 remain truthfully geometry-less, for 99.9377% coverage. All stored geometry is valid, non-empty `MultiPolygon` in SRID 4674. Diagnostics recorded 11,789 duplicate identifiers, 893 invalid source features, 291 active/inactive overlaps, and the 92 missing relevant geometries.
- Import duration/resource observations: complete clean-database import took 5m51.73s, 305.03s user CPU and 6.72s system CPU, with 1,270,360 KiB peak RSS and no swapping. The current-stock plus forced geometry reconciliation took 5m26.21s with 1,100,816 KiB peak RSS and no swapping, proving that a newer SOPLE universe is reconciled even when SIGMINE archive bytes are unchanged. SIGMINE archives total 274,821,995 bytes and the documented temporary-storage allowance is 6 GB.
- Tile/search performance observations: representative low-zoom tile `4/5/8` was 9,674 bytes and 316.73 ms warm (403.17 ms cold); polygon tile `8/96/141` was about 135 KB and 45.45 ms warm. Exact process search was 104.85 ms, filtered search 46.51 ms, and detail lookup 0.86 ms. `EXPLAIN (ANALYZE, BUFFERS)` showed a GiST bitmap index scan for the spatial predicate (3.896 ms) and indexed process/detail lookups; no sequential spatial scan occurs.
- Browser scenarios verified: anonymous nationwide map/list, process search, an actual result click and shareable detail URL, official links, anonymous watch redirect, registration and confirmation through the local mailbox, authenticated watch creation, simulated material import change, one in-app notification, mark-read flow, one Portuguese daily digest, stale/failed-sync banner retaining the last success, and 390×844 responsive rendering without horizontal overflow. Final MapLibre canvas/control smoke had no application console error; screenshots are uncommitted under `/tmp`.
- Known limitations or production-only blockers: deployment must supply an approved HTTPS basemap style/usage allowance, Resend credentials and verified sender domain, and choose a deployment target with PostgreSQL/PostGIS plus GDAL. Product name/branding and the navigational terminology/legal disclaimer still require owner/domain-expert acceptance. Development/test use the working public demo style and Swoosh local/test adapters.
- Failed-attempt evidence retained: acceptance testing exposed and fixed an invalid zero process number, a negative-area constraint violation, Decimal JSON encoding, oversized SQL parameter batches, import transaction timeouts, incorrect SIGMINE weekly scheduling, obsolete configured download filenames, missing HTTP modification provenance, MapLibre 6 worker bundling incompatibility, and map container sizing/CSS precedence. MapLibre is pinned to the verified 5.24.0 single-bundle-compatible version.
- `mix precommit` result: passed on 2026-07-30 with 140 tests, zero failures, and no compile warnings.
