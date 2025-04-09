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

These scripts **require** a container platform:

 - **Most systems**: [Docker](https://www.docker.com/products/docker-desktop). Ensure Docker is installed and running before proceeding.
 - **IBM Power platforms**: Use podman instead of Docker. The installation scripts will automatically detect and use the appropriate container platform.

### What These Scripts Do:

- Install the necessary Docker Compose files (**`.yml`** and **`.env`**) in the directory where they are run.
  📌 *If you want to install Rocketgraph in a specific location, run the script from that directory.*
- Download and start **four separate containers** using [Docker Compose](https://docs.docker.com/compose).
- The application will be available at **[http://localhost](http://localhost)** once the installation is complete.

### Customizing Ports (Optional)

By default, Rocketgraph uses standard ports.
If you need to specify custom ports, you can pass them as parameters to the installation script:

```bash
# Available options:
#   --http-port PORT   Specify custom HTTP port (default: 80)
#   --https-port PORT  Specify custom HTTPS port (default: 443)
#   --xgt-port PORT    Specify custom XGT port (default: 4367)

# Example with custom ports:
curl -sSL https://install.rocketgraph.com/install.sh | sh -s -- --http-port 8080 --https-port 8443 --xgt-port 4368
```

All parameters are optional. If you specify only the HTTP port, the others will use their defaults.


### Managing Rocketgraph Services

After installation, you can manage Rocketgraph services using **Docker Desktop**, which provides a graphical interface to start, stop, and monitor your containers.

If you prefer using the command line, you can run the following commands from the installation directory (where the `.yml` file is located):

```bash
docker compose up -d   # Start the services in the background
docker compose down    # Stop and remove the containers
```

For IBM Power platforms using podman:

```bash
podman-compose up -d   # Start the services in the background
podman-compose down    # Stop and remove the containers
```


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
# Or with custom ports:
bash install.sh --http-port 8080 --https-port 8443 --xgt-port 4368
```

[📟 Launch Terminal Here](x-terminal-emulator://)

#### Windows:
```powershell
powershell -ep Bypass -f install.ps1
```

## 🔒 Cybersecurity Reminder

Before running any script, it’s good practice to review its contents to ensure security and integrity. This helps prevent potential risks, especially in production environments.
