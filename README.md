# Chatwoot Self-Hosted Installer
This shell script automates the deployment of a self-hosted Chatwoot instance using Docker and Docker Compose. It handles the installation of dependencies, configuration of environment variables, database initialization, and integration with Cloudflare Tunnel (Cloudflared).

## Features

* **Dependency Management:** Automatically checks for Docker and Docker Compose. If not found, it installs them using the official installation script and sets up the necessary permissions.
* **Automated Configuration:** Generates the `.env` and `docker-compose.yaml` files in the `/chatwoot` directory.
* **Security:** Automatically generates cryptographically secure random strings for `SECRET_KEY_BASE` and database/Redis passwords.
* **Database Initialization:** Runs the required Rails migrations to prepare the Chatwoot database.
* **Cloudflare Integration:** Checks for `cloudflared`. If missing, installs the package and executes the user-provided Cloudflare Tunnel service token to expose the application.
* **Health Check:** Verifies the installation by polling the local API endpoint upon completion.
* **Logging:** Captures all standard output and errors to a timestamped log file in `/tmp`.

## Prerequisites

* A Linux server (Ubuntu/Debian-based distributions are supported due to `apt-get` usage).
* Root or `sudo` privileges.
* A Cloudflare Tunnel token command (obtained from the Cloudflare Zero Trust dashboard).
* A domain name configured to point to the Cloudflare Tunnel.

## Installation

1.  Download the script to your server:

    ```bash
    wget [https://github.com/dipqi/repository/raw/main/install_chatwoot.sh](https://github.com/yourusername/repository/raw/main/install_chatwoot.sh)
    ```

2.  Make the script executable:

    ```bash
    chmod +x install_chatwoot.sh
    ```

3.  Run the script with sudo permissions:

    ```bash
    sudo ./install_chatwoot.sh
    ```

## Usage

During execution, the script will prompt for two specific inputs:

1.  **Cloudflare Service Command:**
    Paste the full installation command provided by Cloudflare.
    *Example:* `sudo cloudflared service install eyJhIjoi...`

2.  **Frontend URL:**
    Enter the full URL where the Chatwoot instance will be accessible.
    *Example:* `https://chat.example.com`

## Directory Structure

The script creates the following directory and files:

* `/chatwoot/`: Root directory for the installation.
* `/chatwoot/.env`: Environment variables and secrets.
* `/chatwoot/docker-compose.yaml`: Service definitions.
* `/chatwoot/storage`: Persistent storage volume.

## Services

The Docker Compose configuration includes the following services:

* **rails:** The core Chatwoot application server.
* **sidekiq:** Background job processor.
* **postgres:** PostgreSQL database (pgvector/pg16).
* **redis:** Redis data structure store (alpine).

## Troubleshooting

If the installation fails or the health check does not return a 200 OK status, refer to the log file generated during the process. The path to the log file is printed at the start and end of the script execution.

*Example log path:* `/tmp/chatwoot_install_20240101_120000.log`

To view the logs:

```bash
cat /tmp/chatwoot_install_YYYYMMDD_HHMMSS.log
