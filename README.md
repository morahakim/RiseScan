# RiseScan

A native iOS application for uploading, verifying, downloading, and viewing 3D scan assets through a resumable multipart upload workflow.

## Overview

RiseScan is built to demonstrate reliable transfer of large 3D scan files under constrained network conditions.

The application uses a sample 3D scan, so no external scanning hardware or LiDAR sensor is required.

### Key Features

- **3D Preview:** Loads and displays a textured 3D model on the iOS device.
- **Preview-first Upload:** Generates and uploads a lightweight JPEG preview before uploading the original scan.
- **Lossless Original Archive:** Packages the original OBJ, MTL, and texture assets into a ZIP archive without recompressing the source files.
- **Multipart Upload:** Splits the original archive into parts and uploads them independently.
- **Resumable Upload:** Checks server-side upload status and skips parts that have already been uploaded.
- **SHA-256 Integrity Verification:** Calculates and verifies file checksums on the client and server.
- **Original Download:** Downloads the verified original archive, checks its checksum, extracts it, and displays the 3D model.

## Technology Stack

### iOS

- Swift
- SwiftUI
- URLSession
- Background URLSession
- CryptoKit
- RealityKit
- Model I/O
- ZIPFoundation

Minimum deployment target: **iOS 16.0**

### Backend

- Python
- FastAPI
- MinIO / S3-compatible object storage
- Docker Compose

## Project Structure

```text
RiseScan/
├── backend/
│   └── app/
│       └── checksum.py
├── ios/
│   ├── README.md
│   └── RiseScan/
├── sample_scan/
├── tools/
│   ├── check_verify_object.py
│   ├── large_object_check.py
│   ├── make_manifest.py
│   └── verify_bundle.py
├── API.md
├── docker-compose.yml
├── docker-compose.strict.yml
├── .env.example
└── trace.json
```

## Architecture

### Upload Workflow

1. The application loads the sample 3D model.
2. A lightweight JPEG preview is generated and saved locally.
3. The preview is uploaded first.
4. The original OBJ, MTL, and texture files are packaged into a ZIP archive using lossless storage.
5. The application calculates the original archive's SHA-256 checksum.
6. The original archive is uploaded using multipart upload.
7. Before uploading, the client checks the server's upload status.
8. Already completed parts are skipped; missing parts are uploaded.
9. The client submits the completed part list to the backend.
10. The backend verifies the uploaded object's size and SHA-256 checksum.

The original archive is retained locally so that the same scan can reuse the exact same ZIP bytes when resuming an upload.

### Resume Strategy

The upload process uses the server's upload status as the source of truth.

When the application is reopened after an interruption:

- The client retrieves the existing upload session.
- Completed parts are identified from the server response.
- Completed parts are not uploaded again.
- Missing parts are uploaded.
- The upload is completed and verified.

This reduces unnecessary data transfer when the network connection is interrupted or the application is terminated.

### Download Workflow

1. The client requests the original object download.
2. The archive is downloaded from the backend-provided URL.
3. The client calculates the downloaded file's SHA-256 checksum.
4. The checksum is compared with the expected checksum.
5. The ZIP archive is extracted locally.
6. The extracted 3D model is loaded and displayed using RealityKit.

## Backend Checksum Verification

The backend implements `verify_object` in:

```text
backend/app/checksum.py
```

The implementation reads the object incrementally using streamed chunks instead of loading the entire object into memory.

For each chunk, it:

- Updates the SHA-256 hash.
- Tracks the total number of bytes read.
- Continues until the object stream is exhausted.

After reading the object, it checks both the actual size and SHA-256 digest against the expected values.

The response body is closed in a `finally` block to ensure resources are released even if an error occurs.

This approach avoids buffering the entire object in memory and is suitable for large objects.

## Requirements

- macOS
- Xcode
- Docker Desktop
- An iPhone or iPad running iOS 16 or later
- Mac and iOS device connected to the same network
- Network access to backend and MinIO ports

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/morahakim/RiseScan.git
cd RiseScan
```

### 2. Configure Environment Variables

Create a local environment file:

```bash
cp .env.example .env
```

Configure the required backend and MinIO settings in `.env`.

For physical-device testing, make sure the MinIO public endpoint uses an address reachable from the iOS device.

Do not commit `.env` or expose credentials.

### 3. Start Backend and MinIO

```bash
docker compose up -d
```

Check container status:

```bash
docker compose ps
```

Check backend health:

```bash
curl http://localhost:8000/health
```

Expected response:

```json
{"status":"ok"}
```

### 4. Configure the iOS API Endpoint

Open the iOS project and update the API base URL in:

```text
ios/RiseScan/RiseScan/Core/Networking/APIConfig.swift
```

Use the Mac's LAN IP address instead of `localhost`:

```swift
static let baseURL = URL(
    string: "http://<MAC_LAN_IP>:8000"
)!
```

The iPhone or iPad must be able to reach this address over the local network.

Also ensure that the MinIO endpoint configured on the backend is reachable from the physical device.

### 5. Run the iOS Application

1. Open the Xcode project under `ios/RiseScan/`.
2. Select a physical iPhone or iPad as the run destination.
3. Build and run the application.
4. Load the sample 3D scan.
5. Wait for the preview and original uploads to complete.

## Network Testing

The application was tested under a constrained network profile using Apple's Network Link Conditioner.

| Parameter | Configuration |
|---|---:|
| Upload bandwidth | 2 Mbps |
| Download bandwidth | 8 Mbps |
| Round-trip latency | 120 ms |
| One-way delay | 60 ms |
| Packet loss | 0% |

### Resume Test

The resume workflow was tested by terminating the application during an original multipart upload after multiple parts had been uploaded.

The application was reopened and the upload process resumed using the existing server-side upload session.

Previously completed parts were retained, while remaining parts were uploaded before final verification.

## Backend Trace

The backend exposes an upload trace endpoint:

```bash
curl http://localhost:8000/debug/trace
```

Save the trace to the repository root:

```bash
curl http://localhost:8000/debug/trace > trace.json
```

The trace contains upload session information and events such as:

- Upload initiation
- Upload status checks
- Uploaded part snapshots
- Upload completion
- Verification status
- Download requests

`trace.json` is included as supporting evidence of the test run.

## Performance Measurements

Record actual measurements from the constrained network test.

| Operation | Measured Duration |
|---|---:|
| Preview upload | TODO |
| Original upload | TODO |
| Original download | TODO |
| SHA-256 verification | TODO |
| 3D model loading | TODO |

Network profile: 2 Mbps upload / 8 Mbps download / 120 ms RTT.

Measurements should be taken from the actual test run rather than estimated values.

## Validation

Backend checksum verification:

```bash
python3 tools/check_verify_object.py
```

Large-object validation:

```bash
python3 tools/large_object_check.py
```

Bundle validation:

```bash
python3 tools/verify_bundle.py <downloaded.zip>
```

The bundle validation script requires a downloaded ZIP file as its argument.

## Submission Artifacts

The repository includes:

- iOS application source code
- Backend source code
- Sample 3D scan assets
- API documentation
- Docker Compose configuration
- Backend upload trace (`trace.json`)

A separate screen recording demonstrates the upload, interruption, resume, download, and 3D viewing workflow under the constrained network profile.

## Notes

- No LiDAR sensor or external scanning hardware is required.
- The sample scan is used to demonstrate the complete workflow.
- Original scan assets are preserved in the lossless ZIP archive.
- The backend checksum verification streams object data instead of loading the entire object into memory.

## Author

**Mora Hakim**

GitHub: https://github.com/morahakim/RiseScan
