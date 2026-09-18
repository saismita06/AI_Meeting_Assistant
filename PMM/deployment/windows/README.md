# PMM Windows Installer

This folder contains the Windows one-click installer and launcher sources.

Build on Windows from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\PMM\deployment\windows\build-windows-exes.ps1
```

Outputs are written to `dist\windows`:

- `PMM Installer.exe`
- `PMM Launcher.exe`

The installer packages the current repository into `pmm-project.zip`, installs missing prerequisites idempotently, copies PMM to `%ProgramData%\PMM\AI-Meeting-Assistant`, runs Docker Compose, pulls `qwen2.5:3b`, waits for PMM, Whisper, and Ollama containers, then opens `http://localhost:8899`.

Logs are written to `%ProgramData%\PMM\Logs`.
