# 🚀 Rocketgraph Installation

## Quick Installation

### Linux / macOS:

To download and run the installation script in a single command:

```bash
$ curl -sSL https://install.rocketgraph.com/install.sh | sh
```

Before running the installation command, you'll need to open a terminal or command prompt:

macOS:

 - Open the "Terminal" app (located in Applications > Utilities > Terminal)
 - Or use Spotlight Search (press `Cmd + Space`) and type "Terminal"

Linux:

 - Most Linux distributions: Press `Ctrl + Alt + T`
 - Or search for "Terminal" in your desktop environment's application menu

### Windows:

[Download RocketgraphSetup.exe](https://github.com/Rocketgraphai/rocketgraph-setup/releases/latest/download/RocketgraphSetup.exe)

Just download and run the installer. It will automatically install Rocketgraph and all dependencies.

### Prerequisites

Rocketgraph **requires** a container platform:

 - **Most systems**: [Docker](https://www.docker.com/products/docker-desktop). Ensure Docker is installed and running before proceeding.
 - **IBM Power platforms**: Use podman instead of Docker. The installation scripts will automatically detect and use the appropriate container platform.

### What These Installers and Scripts Do:

#### On Linux / macOS:

- Install the necessary Docker Compose files (**`.yml`** and **`.env`**) in the directory where they are run.
  📌 *If you want to install Rocketgraph in a specific location, run the script from that directory.*
- Download and start **four separate containers** using [Docker Compose](https://docs.docker.com/compose).
- The application will be available at **[http://localhost](http://localhost)** once the installation is complete.

#### On Windows, the graphical installer (.exe)/scripts will:

- Install all required dependencies, including Docker Desktop, WSL 2, and the Virtual Machine Platform.
- Set up the necessary Docker Compose files (docker-compose.yml, .env).
- Start Docker Desktop.
- Download and launch the Rocketgraph containers.
- Automatically open your default browser to http://localhost and the port chosen when setup completes.

### Customizing Ports (Optional)

By default, Rocketgraph uses standard ports.
If you need to specify custom ports, you can pass them as parameters to the installation script.  The available options are:

| Option            | Description                              |
|-------------------|------------------------------------------|
| --http-port PORT  | Specify custom HTTP port (default: 80)   |
| --https-port PORT | Specify custom HTTPS port (default: 443) |

Here's an example with custom ports:
```bash
$ curl -sSL https://install.rocketgraph.com/install.sh | sh -s -- --http-port 8080 --https-port 8443
```

All parameters are optional. If you specify only the HTTP port, the others will use their defaults.


### Managing Rocketgraph Services

After installation, you can manage Rocketgraph services using **Docker Desktop**, which provides a graphical interface to start, stop, and monitor your containers.

If you prefer using the command line, you can run the following commands from the installation directory (where the `.yml` file is located):

```bash
$ docker compose up -d   # Start the services in the background
$ docker compose down    # Stop and remove the containers
```

For IBM Power platforms using podman:

```bash
$ podman-compose up -d   # Start the services in the background
$ podman-compose down    # Stop and remove the containers
```


For more details, refer to the **[Mission Control Guide](https://github.com/Rocketgraphai/rocketgraph/blob/main/README.md).**

## Alternate Installation

Alternatively, you can manually download and run the installation scripts.

### Download:
- **[install.sh (Linux/Mac)](install.sh)**
- **[install.ps1 (Windows)](install.ps1)**

### Run:
#### Linux / macOS:
```bash
$ bash install.sh
```

Or with custom ports:

```bash
$ bash install.sh --http-port 8080 --https-port 8443
```

#### Windows:

Open a terminal:

 - Right-click on the Start button and select "Terminal"
 - Or press Win + X and select "Terminal"

Run this command to download and execute the installer script directly from the web:

```powershell
powershell -ep Bypass -c "iex (iwr -useb 'https://install.rocketgraph.com/install.ps1')"
```

If you already downloaded the script manually, run it like this:

```powershell
powershell -ep Bypass -f install.ps1
```

## 🔒 Cybersecurity Reminder

Before running any script, it’s good practice to review its contents to ensure security and integrity. This helps prevent potential risks, especially in production environments.

## More Resources

For more details about the Windows installer itself, including release notes and troubleshooting, see the  
[Rocketgraph Installer Repository](https://github.com/Rocketgraphai/rocketgraph-setup)
