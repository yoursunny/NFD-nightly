# NFD-nightly APT repository

This branch contains scripts to run an APT repository for NFD-nightly.
It downloads the NFD nightly packages built in GitHub Actions and stored as artifacts, and prepares them into an APT repository with [reprepro](https://wiki.debian.org/DebianRepository/SetupWithReprepro).

These steps are relevant only if you want to run a mirror APT repository.
To install from the hosted APT repository, please see https://nfd-nightly.ndn.today for instructions.

## Setup HTTP Server

1. Install [Caddy](https://caddyserver.com/docs/install) HTTP server
2. Create `/home/web` directory and make it accessible to Caddy:
    ```bash
    sudo mkdir /home/web
    sudo chown -R $(id -un):www-data /home/web
    sudo chmod g+ws /home/web
    sudo adduser $(id -un) www-data
    ```
3. Clone this branch to `/home/web/NFD-nightly-apt` directory:
    ```bash
    git clone --single-branch --branch apt \
      https://github.com/yoursunny/NFD-nightly.git NFD-nightly-apt
    ```
4. Copy `Caddyfile` to `/etc/caddy/Caddyfile`, edit the hostname as appropriate, then restart Caddy server

## Setup Update Script

1. `./docker-build.sh`
2. Copy `sample.env` to `.env`, and enter a GitHub Personal Access Token in `.env`
3. Run `/home/web/NFD-nightly-apt/docker-update.sh` script to download packages from GitHub Actions artifacts
4. Setup crontab to run this script weekly, 24 hours after the GitHub Actions trigger
