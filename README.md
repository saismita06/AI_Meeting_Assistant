# 🎙️ AI Meeting Assistant (PMM)

A secure, fully offline, and privacy-first AI-powered meeting assistant. It leverages local containers for audio transcription (**WhisperX**), local large language models (**Ollama / Qwen**), and structured summarization.

---

## 🏗️ Architecture

```
                 ┌────────────────────────────────┐
                 │          User Web UI           │
                 └───────────────┬────────────────┘
                                 │ HTTP / WebSockets
                                 ▼
                 ┌────────────────────────────────┐
                 │       Flask App (PMM)          │
                 └──────┬──────────────────┬──────┘
                        │                  │
      ASR Engine API    ▼                  ▼  Local LLM API (OpenAI Compatible)
 ┌───────────────────────────┐        ┌───────────────────────────┐
 │        WhisperX           │        │         Ollama            │
 │ (whisperx-asr-service)    │        │      (qwen3:8b)           │
 └───────────────────────────┘        └───────────────────────────┘
```

---

## ✨ Key Features

- 📤 **Audio & Video Intake** – Upload standard audio formats or video files directly via the responsive web interface.
- 🗣️ **WhisperX Transcription** – High-accuracy local speech-to-text with multi-lingual support.
- 👥 **Speaker Diarization** – Automatically identifies who said what throughout the meeting.
- 🎙️ **Voice Profiles** – Recognizes repeat speakers across different recordings using voice embeddings.
- 🧠 **Local LLM Summaries** – Automatically generates structured JSON summaries (Overview, Key points, Decisions, Action Items) using local Ollama models.
- 📑 **Rich Export Pipeline** – Download transcripts and summaries in various formats:
  - **PDF** (fully styled with ReportLab, supporting tables, page flowing, and Unicode/Chinese characters)
  - **Word Document (DOCX)**
  - **Markdown**
  - **Plain Text (TXT)**
- 🔒 **Privacy-First & Secure** – Runs 100% offline. No data leaves your local deployment environment. Includes built-in multi-user authentication.

---

## 🚀 Quick Start

### 📋 Prerequisites

Before running the application, make sure you have the following installed on your host system:
1. [Docker](https://www.docker.com/) and **Docker Compose**.
2. An internet connection (for the initial build and model pulls).

---

### 📦 Setup & Deployment

1. **Clone the Repository**
   ```bash
   git clone https://github.com/your-username/PXE_MeetingMitra.git
   cd PXE_MeetingMitra
   ```

2. **Configure Environment Variables**
   * Create a root-level `.env` file and add your Hugging Face Hub token (required by WhisperX to download the PyAnnote speaker diarization model):
     ```env
     HF_TOKEN=your_huggingface_token_here
     ```
   * Configure application settings in the `PMM/.env` file. Offline default settings are:
     ```env
     TRANSCRIPTION_CONNECTOR=asr_endpoint
     TRANSCRIPTION_BASE_URL=http://whisper-asr:9000/v1
     TEXT_MODEL_BASE_URL=http://ollama:11434/v1
     TEXT_MODEL_NAME=qwen3:8b
     ```

3. **Build & Start Services**
   Run the following command to compile the web application, spin up the offline engines, and automatically pull the configured Ollama model:
   ```bash
   docker compose up -d --build
   ```

---

## 🔄 Automated Ollama Model Pull

The project's `docker-compose.yml` automatically triggers Ollama to download and initialize the configured LLM (e.g. `qwen3:8b`) upon container startup. 

During the first launch, the `ollama` service will:
1. Start the Ollama server in the background.
2. Automatically run `ollama pull qwen3:8b`.
3. Save the model data to the persistent `ollama-data` Docker volume so it persists across container restarts.

No manual pulling commands are required!

---

## 🛠️ Verification & Troubleshooting

Once all containers are running, you can verify the status of the offline services using these commands:

### Check Container Status
```bash
docker compose ps
```

### View Application Logs
```bash
docker compose logs -f pmm
```

### Verify Transcription Connection
Ensure the Python app connects correctly to the WhisperX service:
```bash
docker compose exec pmm python -c "from src.services.transcription.registry import get_registry; r=get_registry(); c=r.get_active_connector(); print('Status:', r.get_active_connector_name(), c.base_url, 'Healthy:', c.health_check())"
```

### Verify Ollama LLM Connection
Ensure the Ollama API server is active and accessible:
```bash
docker compose exec pmm python -c "import os, httpx; print('Ollama Status Code:', httpx.get(os.environ['TEXT_MODEL_BASE_URL'].rstrip('/') + '/models', timeout=10).status_code)"
```

---

## 📄 License

Distributed under the GNU Affero General Public License (AGPLv3). See `LICENSE` for details.
"# AI_Meeting_Assistant" 
