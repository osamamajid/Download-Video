# Video Downloader Backend

Backend API for video downloader application.

## Installation

```bash
npm install
```

## Requirements

- Node.js 14+
- FFmpeg (for audio conversion)

### Install FFmpeg

**Windows:**
Download from https://ffmpeg.org/download.html and add to PATH

**Linux:**
```bash
sudo apt-get install ffmpeg
```

**Mac:**
```bash
brew install ffmpeg
```

## Run

```bash
npm start
# or for development
npm run dev
```

Server will run on http://localhost:3000

## API Endpoints

- `POST /api/video/info` - Get video information
- `POST /api/video/download` - Download video
- `POST /api/audio/download` - Download audio only
- `GET /api/files` - Get all downloaded files
- `DELETE /api/files/:type/:filename` - Delete a file



