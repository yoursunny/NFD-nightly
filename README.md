# NFD-nightly APT repository

This branch contains scripts to run an APT repository for NFD-nightly.
It downloads the NFD nightly packages built in GitHub Actions and stored as artifacts, and prepares them into an APT repository with [reprepro](https://wiki.debian.org/DebianRepository/SetupWithReprepro).

These steps are relevant only if you want to run a mirror APT repository.
To install from the hosted APT repository, please see https://nfd-nightly.ndn.today for instructions.

## Installation

Recommended OS: Debian 11 or Ubuntu 20.04

1. `sudo apt install reprepro unzip`
2. Install [Caddy](https://caddyserver.com/docs/install) HTTP server
3. Create `/home/web` directory and make it accessible to Caddy:
    ```bash
    sudo mkdir /home/web
    sudo chown -R $(whoami):www-data /home/web
    sudo chmod g+ws /home/web
    sudo usermod -a -G www-data $(whoami)
    ```
4. Clone this branch to `/home/web/NFD-nightly-apt` directory:
    ```bash
    git clone --single-branch --branch apt \
      https://github.com/yoursunny/NFD-nightly.git NFD-nightly-apt
    ```
5. Copy `sample.env` to `.env`, and enter a GitHub Personal Access Token in `.env`
6. Execute `/home/web/NFD-nightly-apt/update.sh` script to download packages from GitHub Actions artifacts
7. Setup crontab to execute this script weekly, 24 hours after the GitHub Actions trigger
8. Copy `Caddyfile` to `/etc/caddy/Caddyfile`, edit the hostname and IP addresses as appropriate, then restart Caddy server
