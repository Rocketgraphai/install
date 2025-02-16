# Rocketgraph Install Scripts

## To download and run the installation script in one command:

```bash
# For Linux/Mac
curl -sSL https://install.rocketgraph.ai/install.sh | sh
```

```powershell
# For Windows
powershell -ExecutionPolicy Bypass -Command "& { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://install.rocketgraph.ai/install.ps1')) }"
```

## Alternatively, you can download the installation scripts and run them in your shell:

- [Download install.sh (Linux/Mac)](install.sh)
- [Download install.ps1 (Windows)](install.ps1)

## To run these scripts, use the following commands in your shell:

```bash
# For Linux/Mac
bash install.sh
```

```powershell
# For Windows
powershell -ExecutionPolicy Bypass -File install.ps1
```

**Cybersecurity Reminder:** It is always a good practice to review the contents of any script before running it. This ensures that you understand what the script does and helps maintain the security and integrity of your system. For commercial-quality applications, following this practice is essential to prevent potential security risks.
