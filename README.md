# 🚀 Rocketgraph Install Scripts

## Quick Installation

To download and run the installation script in a single command:

### Linux / macOS:

```bash
curl -sSL https://install.rocketgraph.com/install.sh | sh
```

### Windows:

```powershell
powershell -ep Bypass -c "iex (iwr -useb 'https://install.rocketgraph.com/install.ps1')"
```

### Prerequisites

These scripts **require** [Docker](https://www.docker.com/products/docker-desktop). Ensure Docker is installed and running before proceeding.

### What These Scripts Do:

- Install the necessary Docker Compose files (**`.yml`** and **`.env`**) in the directory where they are run.
  📌 *If you want to install Rocketgraph in a specific location, run the script from that directory.*
- Download and start **four separate containers** using [Docker Compose](https://docs.docker.com/compose).
- The application will be available at **[http://localhost](http://localhost)** once the installation is complete.

### Managing Rocketgraph Services

After installation, you can manage Rocketgraph services using **Docker Desktop**, which provides a graphical interface to start, stop, and monitor your containers.

If you prefer using the command line, you can run the following commands from the installation directory (where the `.yml` file is located):

```bash
docker compose up -d   # Start the services in the background
docker compose down    # Stop and remove the containers
```

Alternatively, you can manage containers using the **Docker Desktop** application.

For more details, refer to the **[Mission Control Guide](https://github.com/Rocketgraphai/rocketgraph/blob/main/README.md).**

## Local Installation

Alternatively, you can manually download and run the installation scripts.

### Download:
- **[install.sh (Linux/Mac)](install.sh)**
- **[install.ps1 (Windows)](install.ps1)**

### Run:
#### Linux / macOS:
```bash
bash install.sh
```
#### Windows:
```powershell
powershell -ep Bypass -f install.ps1
```

## 🔒 Cybersecurity Reminder

Before running any script, it’s good practice to review its contents to ensure security and integrity. This helps prevent potential risks, especially in production environments.
