# API

The contract of the provided server. Your client must follow the rules below (`complete` only works once you have implemented `verify_object`).

Base URL `http://localhost:8000`. JSON unless noted. No authentication.

## Contents

- [At a glance](#at-a-glance)
- [How an upload works](#how-an-upload-works)
- [Endpoints](#endpoints)
- [Resuming, retrying and failing](#resuming-retrying-and-failing)
- [Errors](#errors)
- [Server restarts](#server-restarts)
- [Debug](#debug)

## At a glance

| Endpoint | Purpose |
|---|---|
| `GET /health` | Liveness check |
| `POST /uploads` | Start (or resume) an upload; returns presigned part URLs |
| `GET /uploads/{upload_id}` | Status and the parts the server holds |
| `POST /uploads/{upload_id}/complete` | Assemble the parts and verify the file |
| `GET /uploads/{upload_id}/download` | Presigned download URL (verified uploads only) |
| `GET /scans/{scan_id}` | Status of both uploads of a scan |
| `GET /debug/trace` | Read-only record of what the server saw |

## How an upload works

A scan has two uploads, identified by a client-chosen `scan_id` and a `kind`:

| `kind` | What it is |
|---|---|
| `original` | **One file**: a ZIP of the scan's files. They must come back byte-identical. Folder layout inside the ZIP is up to you. |
| `preview` | **One file**: a smaller derivative. The format is your choice; the server does not inspect it. |

`scan_id` is a UUID string in any usual spelling and is case-insensitive: an uppercase `UUID().uuidString` and its lowercase form name the same scan. `upload_id` is case-insensitive too (the server hands out lowercase ids).

Each file is sent as S3 multipart parts through presigned URLs, **straight to storage, not through the server**. The rules:

- **Part size.** `part_size` is chosen by the server, **between 5 MiB and 8 MiB** (currently 5 MiB). Part numbers start at 1; part `n` covers bytes `[(n-1)*part_size, n*part_size)`. The last part may be smaller.
- **Max size.** `size_bytes` is at most `10000 * part_size` (S3 allows 10000 parts per upload); a larger value is a `422`.
- **Sending a part.** Use a plain `PUT` with **no extra headers**. Keep the `ETag` exactly as storage returned it (including quotes); you send it back in `complete`.
- **URL host.** Every presigned URL (upload and download) is built for the host in the environment variable `S3_PUBLIC_ENDPOINT_URL` (default `http://localhost:9000`). Our automated check runs with the default. On a physical device, set it to your laptop's LAN address (or a tunnel) so the phone can reach it.
- **URL lifetime.** Part URLs are valid for **1 hour**. For fresh ones, call `POST /uploads` again: same upload, same part plan, newly signed URLs.
- **Checksum.** `sha256` is the hex SHA-256 of the whole file: 64 hex characters, lowercase (uppercase is accepted too). Anything else, such as a base64 digest, is a `422` and leaves the upload as it was, so `complete` can be retried.

The usual flow: `POST /uploads` → `PUT` each part → `POST /uploads/{id}/complete` → `GET /uploads/{id}/download`.

## Endpoints

### `GET /health`

Returns `{"status":"ok"}`.

### `POST /uploads`

Starts an upload, or resumes the existing one for this `(scan_id, kind)`.

Request:

```json
{"scan_id": "…", "kind": "preview" | "original", "filename": "scan.zip", "size_bytes": 12345678}
```

`filename` must be non-empty; it is informational only and the server never uses it.

Response:

```json
{"upload_id": "…", "part_size": 5242880,
 "parts": [{"part_number": 1, "url": "http://…presigned PUT…"}, …]}
```

Calling it again for the same `(scan_id, kind)` is **idempotent**; see [Resuming, retrying and failing](#resuming-retrying-and-failing) for what comes back in each state.

### `GET /uploads/{upload_id}`

Response:

```json
{"scan_id": "…", "kind": "…", "status": "in_progress", "total_parts": 3,
 "parts": [{"part_number": 1, "etag": "\"…\"", "size": 5242880}], "reason": "…"}
```

- `status` is one of `in_progress`, `verified`, `failed`. `reason` appears only when `failed`, and says why (as in `complete`).
- `parts` lists the parts the server already holds, and is `[]` unless `status` is `in_progress`. Once `complete` has the parts (while it assembles and verifies them, and after that), it lists every part.

### `POST /uploads/{upload_id}/complete`

Assembles the parts, then checks the assembled object with `verify_object` in `backend/app/checksum.py` (the piece you implement).

Request:

```json
{"sha256": "<64 hex characters>", "parts": [{"part_number": 1, "etag": "\"…\""}, …]}
```

Response (HTTP 200 in both outcomes):

```json
{"status": "verified"}
{"status": "failed", "reason": "checksum_mismatch"}
```

- `verified` only if the object has exactly `size_bytes` bytes and its server-side SHA-256 equals `sha256`.
- `reason` is what `verify_object` returned (for example `checksum_mismatch`), or `upload_expired` (see below). If `verify_object` returns anything but `None` or a non-empty string, the upload fails with `verify_object_bad_return`.
- **Retry-safe**, also while an earlier call is still running. On an upload that is already `verified` or `failed` it returns that same result with HTTP 200; the stored result takes precedence over the request body.
- **A wrong parts list** is a `400` whose `detail` names the part numbers that are missing, extra or duplicated, a part other than the last that is smaller than 5 MiB, or an etag that does not match the stored part. The upload stays `in_progress`: `GET /uploads/{id}` lists what storage holds; re-send the part, then retry `complete`.
- **If the check cannot run**, the upload stays `in_progress` and a later `complete` tries again:
  - `501` while `verify_object` is not implemented;
  - `500` if it raised an error. `detail` names the error type and message; `docker compose logs backend` has the full traceback.

### `GET /uploads/{upload_id}/download`

Response: `{"url": "…", "expires_in": 600}` (`expires_in` in seconds, at most 3600).

- `409` unless `status` is `verified`. A failed upload is never downloadable.
- The `url` is signed for `GET` only (a `HEAD` on it is a `403`). `Range` requests work.

### `GET /scans/{scan_id}`

Response: `{"preview": <status or null>, "original": <status or null>}`. Each value is the upload's status object (it may include additional fields). An unknown scan returns `200` with nulls.

## Resuming, retrying and failing

`POST /uploads` is idempotent on `(scan_id, kind)`, so a restarted client can resume instead of starting over:

| State of the existing upload | What `POST /uploads` returns |
|---|---|
| `in_progress` | The same `upload_id` and part plan. `409` if `size_bytes` differs. Once `complete` has the parts, `parts` is `[]`: nothing is left to send, retry `complete`. |
| `verified` | The same `upload_id` and `parts: []` (`409` if `size_bytes` differs); check `GET /uploads/{upload_id}` for `status`. A verified `(scan_id, kind)` is final: it is never replaced, and no bytes are compared. |
| `failed` | A **new** upload: new `upload_id`, new part plan. Send every part again, then `complete` the new id. The failed one stays failed. |

Notes:

- **There is no abort.** A zip rebuilt with a different size for a `scan_id` whose upload is still `in_progress` gets the `409` above, and bytes that differ at the same size fail at `complete`. Keep the exact zip you started with (or build it byte-deterministically), plus its size and SHA-256, in your persisted state across app restarts, or use a new `scan_id`.
- **Expiry.** Storage drops a multipart upload that is left unfinished for too long (MinIO: 24 h by default). The server then marks it `failed` with reason `upload_expired` (`GET /uploads/{upload_id}`, `POST /uploads` and `complete` all notice it). The next `POST /uploads` starts a new upload, and every part has to be sent again.

## Errors

| Status | When |
|---|---|
| `400` | `complete` got an incomplete or unassemblable parts list. |
| `404` | Unknown `upload_id`. |
| `409` | Wrong state: `size_bytes` differs from the existing upload, or `download` on an upload that is not `verified`. |
| `422` | Bad request body or path: an invalid `scan_id` (body or path), an empty `filename`, `size_bytes` below 1 or above the limit, a `size_bytes` or `part_number` that is not a JSON integer (`"100"`, `true` and `100.0` are refused), or a `sha256` that is not 64 hex characters. |
| `500` / `501` | `verify_object` raised / is not implemented (see `complete`). |

## Server restarts

The server keeps its state (uploads, scans, the trace) **in memory only**. After a restart every `upload_id` is a `404` and every scan is unknown (`GET /scans/{scan_id}` returns nulls). Start again with `POST /uploads` and re-send every part. Objects and parts already in storage from before the restart are orphaned (harmless).

## Debug

`GET /debug/trace` returns, per upload (oldest first), the calls the server saw: every `POST /uploads`, `GET /uploads/{id}`, `complete` (with its result) and download, each with a timestamp (Unix seconds), plus snapshots of the parts storage held whenever the server listed them.

It is read-only, kept in memory only, and changes nothing above. The hiring team uses it to review a run of your app (you submit it as `trace.json`, see `README.md`); you may use it to debug yours.
