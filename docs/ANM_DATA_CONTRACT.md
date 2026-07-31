# ANM data-contract evidence

This document records the Slice 0 source spike for the Jazida Phoenix MVP. It is implementation evidence, not an ANM publication. Official raw labels and source files remain authoritative.

## Snapshot

Observed on 2026-07-29 using files published by ANM on 2026-07-28.

| Source | Local rows/features | SHA-256 |
| --- | ---: | --- |
| SOPLE `EstoqueAreas.csv` | 147,655 rows; 147,602 strict valid process identifiers | Source changes daily; checksum is recorded by the future importer |
| SOPLE `ResultadoRodadaDisponibilidade.csv` | 31,841 rows | Source changes after homologation/monthly |
| SIGMINE active `BRASIL.zip` | 268,765 feature rows | `07909e08d04ece067c500af60078881748030a430340f1b300c50eb314810380` |
| SIGMINE `PROCESSOS_INATIVOS.zip` | 664,519 feature rows | `1647003c5d8215d49c691e9c9ade095dc3cb789ea5d629b6e01e73059a2ec645` |

The two SIGMINE archives expanded to approximately 1.01 GB and loaded into the isolated PostGIS spike database in approximately 13 seconds total on the development workstation.

## Identifier contract

Accept only a trimmed value matching `\A\d{1,6}/\d{4}\z`, then left-pad the numeric part to six digits. Examples:

- `844001/2022` remains `844001/2022`.
- `100/1966` becomes `000100/1966`.
- `844.001/2022` is not accepted as a SOPLE identifier; SIGMINE's `DSProcesso` is normalized separately by removing the one expected thousands separator before applying the same strict contract.

Do not normalize arbitrary text by stripping every non-digit character. The live SOPLE stock contained 53 invalid process identifiers consisting of SQL-injection/security-test payloads such as `844001/2022' OR 1=1--` and `WAITFOR...`. They must be rejected as source warnings and must never reach SQL or shell construction.

## Join coverage

The strict SOPLE stock plus published round universe contained 147,607 unique valid process numbers. Joining to the union of active and inactive SIGMINE `PROCESSO` values produced:

| Measure | Count |
| --- | ---: |
| Strict valid SOPLE/round processes | 147,607 |
| Processes with SIGMINE geometry | 147,368 |
| Missing geometry | 239 |
| Coverage | 99.8381% |

Stock-only coverage by official stock status:

| `SituacaoEstoque` | Total | Matched | Missing | Coverage |
| --- | ---: | ---: | ---: | ---: |
| `Para Análise` | 64,005 | 63,889 | 116 | 99.819% |
| `Não apta para Disponibilidade` | 57,740 | 57,627 | 113 | 99.804% |
| `Apta para Disponibilidade` | 17,513 | 17,512 | 1 | 99.994% |
| `Em Análise` | 8,344 | 8,335 | 9 | 99.892% |

The gate's 99% coverage threshold is satisfied. Missing geometry is truthful product state: keep the process searchable, show that no current official polygon was matched, and record an import warning. Do not fabricate geometry or hide the process.

## Geometry contract

- Both shapefiles declare SIRGAS 2000 (`EPSG:4674`).
- GDAL imported the unmodified sources as `MultiPolygonZM`; production import must pass `-dim XY`/force 2D and store `geometry(MultiPolygon, 4674)`.
- The combined sources contained 933,284 feature rows, no null/empty geometry, and 893 invalid feature geometries.
- Within the relevant SOPLE universe, 283 invalid rows affected 280 processes.
- Eleven thousand seven hundred eighty-nine process numbers had multiple source rows; a process had as many as 281 rows.
- Seven relevant process numbers existed in both active and inactive sources.

Production consolidation therefore must:

1. Prefer active rows when a process exists in both active and inactive sources.
2. Force geometry to 2D.
3. Apply `ST_MakeValid` and extract polygonal components only.
4. Union all polygonal rows for the chosen source with `ST_UnaryUnion(ST_Collect(...))`.
5. Coerce the result to `MultiPolygon`, SRID 4674.
6. Reject/log a process if the repaired result is empty or non-polygonal.

Applying those rules produced 147,368 unique, non-empty, valid `MultiPolygon` records with SRID 4674.

## Official status vocabulary and cautious display categories

Always store and show the raw label. The display category is a navigation aid and must not imply a legal conclusion.

### Stock pipeline

| Raw `SituacaoEstoque` | Display category |
| --- | --- |
| `Para Análise` | `pending_analysis` |
| `Em Análise` | `under_analysis` |
| `Apta para Disponibilidade` | `eligible` |
| `Não apta para Disponibilidade` | `not_eligible` |

### Latest edital/round result

| Raw status | Display category |
| --- | --- |
| `Aguardando Leilão` | `awaiting_auction` |
| `Livre` | `free` |
| `Conquistada`, `Arrematada` | `awarded` |
| `Requerido` | `requested` |
| `Não Requerida` | `unrequested` |
| `Suspensa` | `suspended` |
| `Retirada` | `withdrawn` |
| `Edital Cancelado` | `cancelled` |

An unrecognized nonblank status maps to `unknown`, remains visible verbatim, and creates an import warning. A blank latest-edital status does not override the stock-pipeline category.

## Vector-tile feasibility

A consolidated table of all 147,368 matched process geometries was indexed with GiST. A representative zoom-8 tile intersected 1,267 processes, produced a 90,314-byte MVT payload, and executed in approximately 26 ms with a warm cache. The query used the spatial index; no sequential spatial scan occurred.

A representative zoom-4 tile intersected approximately 50,000 processes, proving that raw low-zoom polygons are not acceptable. The implementation must use aggregates/centroids at low zoom and detailed polygons only at inspection zooms.

## Accepted gate outcome

- Join coverage exceeds 99%.
- Invalid upstream identifiers and unknown statuses are explicit warnings, never permissive fallbacks.
- Geometry repair/consolidation rules produce valid canonical geometry.
- PostGIS MVT generation is fast enough for the proposed architecture at inspection zooms.
- Full-source download and staging are operationally reasonable, but temporary disk usage must be bounded and monitored.
