# Rise Bionics: Scan Upload

**Time:** one week.

## The problem

A clinician scans a patient's limb on an iPad and sends it to our servers. Clinic connectivity in India is often a weak mobile signal, the app gets backgrounded, and the phone can be killed at any moment. The scan has to arrive **exactly as scanned**, and the fabricator should see something quickly.

`sample_scan/` holds one scan (OBJ + MTL + texture) to use as the capture output. You don't need a Structure Sensor for the assignment.

## What we need

**A mock server is provided.** `docker compose up` starts it (`backend/`, FastAPI) with MinIO as the S3 storage. It
implements `API.md` and works out of the box, except for one piece you write (below).

**(a) An iOS client** that, against that server:

- **Packages the scan.** Zips the scan on the device (the `original`) and makes a small lossy **preview** from it.
- **Uploads preview first.** The preview goes up first, then the full lossless original follows in the (background `URLSession`). The app shows which step it is on. The original is never replaced by the preview.
- **Resumes.** If the app is killed or the network drops, uploading continues where it stopped, 
  (a part that was in flight is re-sent, finished parts are not). There is no abort, and re-initiating a scan whose upload is in progress with a zip of another size is a `409`: keep the exact zip file (or make the zip byte-deterministic) with its size and SHA-256 in your persisted state, or use a new `scan_id`. A verified upload is
  final (see `API.md`): a scan whose bytes changed after that needs a new `scan_id`.
- **Protects integrity.** The app computes the SHA-256 of what it uploads, and verifies that what it downloads
  matches it.
- **Round-trips.** The app downloads what was uploaded and shows the mesh in 3D, preview first.
- Works on a real iPhone or iPad against the server on your laptop, not only the simulator.

**(b) One server task:** implement `verify_object` in `backend/app/checksum.py`, which `complete` calls to check the
assembled object. Until then `complete` returns `501`. This is the only server change we expect; everything else in
`backend/` is ours, and you shouldn't need to touch it. Your `verify_object` is also run against a very large object
(about 1 GiB) on a server limited to 512 MiB of RAM with little temporary disk, so it must stream the object, neither
reading it whole into memory nor copying it to disk. 

Tell us what you chose and why (preview format, part handling, what you would change on a slower link).

## Test conditions

Everything is judged on a **poor clinic 4G link**: **2 Mbps up, 8 Mbps down, 120 ms round trip**.
Use Network Link Conditioner (custom profile, 60 ms delay each way) on the device to reproduce it. The server and its
storage run in `docker compose` capped at **2 CPU cores and 4 GB RAM** in total (the server itself gets 1.5 CPU and
3 GB), so don't buffer whole files in memory.

Aim for: the preview usable within about a few seconds of starting the upload, and the original finishing in roughly its size divided by the bandwidth, plus 25%. In your README, report what you actually measured.

## Scope

The app is **one screen**: a 3D view, a progress indicator, and upload and download buttons. We don't care about design or polish, only how the transfer behaves. There is no login and no database design to build. Keep it minimal and tell us what you would do with more time.

## Rules

- The zip extracts into a `rise-scan-assignment/` folder; work in it.
- `docker compose up --build` starts MinIO and the server on `http://localhost:8000`, unless `BACKEND_PORT` is set
  (`cp .env.example .env` and edit it, or `export BACKEND_PORT=8080`; use another port if 8000 is taken).
  For a real device, set `S3_PUBLIC_ENDPOINT_URL` the same way to your laptop's LAN address (or a tunnel); see
  `.env.example` and `API.md`.
- The server runs `backend/app/checksum.py` as built into its image: after editing it, run
  `docker compose up -d --build`, or the running server keeps the old code (and `complete` keeps returning `501`).
  If `complete` returns `500`, its `detail` names the error; `docker compose logs backend` shows the traceback.
- The storage port 9000 is open to your network with default credentials: use a trusted network, and only the
  sample scan, never real patient data, on this stack.
- Use git and commit as you go (this folder comes without history, so `git init` inside `rise-scan-assignment/` first); we read the history. No secrets in the repo.
- Use any tools you like, AI included. You'll walk us through your code in a follow-up call.

## Submit

1. Your work: a zip of your repo (with its `.git` folder), or a link to a repo you share with us (invite us).
2. A 3–5 minute screen recording **under the throttled profile**: upload, kill the app mid-upload, resume,
   then download and view. Kill it late in the original upload, once at least two parts have finished, so the resume
   is visible.
3. `trace.json` in the repo root: restart the server (`docker compose restart backend`) so it is empty, do exactly
   one run (the one above), then save it right after: `curl http://localhost:8000/debug/trace > trace.json` (your
   port if you changed it; see `API.md`, Debug). Only the newest scan in the trace is read, and a run where the app
   was never killed is flagged.
4. A README with your handover notes, including your measured latencies.

## Next

We run automated checks on your `verify_object` and on your `trace.json`, and review your code and recording. If it
goes well, a call covers your design, a small live change, and questions on AWS, health-data privacy and depth sensors.

## Helpers

- `tools/make_manifest.py` writes `sample_scan/manifest.json` (SHA-256 of every file).
- `tools/verify_bundle.py downloaded.zip` checks that a downloaded bundle is byte-identical to the originals.
- `tools/check_verify_object.py` checks your `verify_object` against the running stack's storage (right object, wrong
  digest, changed byte, size off by one, missing object): `cd backend && uv run python ../tools/check_verify_object.py`
  (or any Python with `boto3`). It imports your file directly, so it can pass while the running server still has the
  old code: rebuild with `docker compose up -d --build`. It does not cover the very large object.
- `tools/large_object_check.py` covers the very large object through the running server: it uploads about 1 GiB of
  zeros and expects `verified`, then the same with one changed byte and expects `failed`. Start the stack with the
  limits it is judged under (512 MiB of RAM, read-only filesystem with a 64 MiB `/tmp`), then run it (Python 3.12,
  standard library only; a few minutes):
  ```
  docker compose -f docker-compose.yml -f docker-compose.strict.yml up -d --build
  python tools/large_object_check.py        # another port: export BACKEND_PORT (or BACKEND_URL) first
  ```
  `docker compose up -d --build` (without the second file) goes back to the normal limits.
