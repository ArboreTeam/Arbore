# Models Directory

This directory contains 3D USDZ model files served by the backend.

## Current Models

- `Cactus.usdz` (3.3 MB)
- `Dyspis_Lutescens.usdz` (3.3 MB)
- `Livistona_Chinensis.usdz` (3.9 MB)
- `Monstera_Deliciosa.usdz` (42 MB)
- `Pilea.usdz` (2.9 MB)
- `Pothos.usdz` (2.0 MB)

**Total: ~57 MB**

## API Endpoint

Models are served via the protected endpoint:

```
GET /models/:filename
```

**Requirements:**
- Valid API Key (X-API-Key header)
- Firebase Authentication token (Authorization Bearer header)

**Example:**
```bash
curl -H "X-API-Key: YOUR_API_KEY" \
     -H "Authorization: Bearer YOUR_FIREBASE_TOKEN" \
     http://localhost:8080/models/Monstera_Deliciosa.usdz
```

## Adding New Models

1. Place `.usdz` files in this directory
2. Update the plant's `modelURL` field in MongoDB to match the filename
3. The iOS app will automatically download and cache the model

## Security

- Only `.usdz` files are allowed
- Path traversal attacks are prevented
- Authentication required (API Key + Firebase token)

## Git

USDZ files are excluded from git (.gitignore) due to their large size.
Deploy them separately to your production server.
