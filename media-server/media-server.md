# Media Server Deployment Guide

This guide explains how to deploy and configure a modular media server system using Docker Compose. The media server has been organized into three separate stacks for better management and scalability:

1. **media-download.yml**: VPN tunnel and download clients
2. **arr-stack.yml**: Media management and automation services
3. **jelly-stack.yml**: Media server and request management

---

## Prerequisites

1. **Docker and Docker Compose**: Ensure Docker and Docker Compose are installed on your system.
2. **Environment Variables**: Update the `.env` file with your credentials and directory paths.
   - Example:
     ```env
     OPENVPN_USER=your_vpn_username
     OPENVPN_PASSWORD=your_vpn_password
     MEDIA_SERVER_MEDIA=/path/to/your/media
     ```

---

## Stack Descriptions

### 1. Media Download Stack (media-download.yml)

This stack manages secure downloading through a VPN tunnel:

- **Gluetun**: VPN tunnel container that routes traffic for download clients
- **qBittorrent**: Torrent download client (runs only through VPN)
- **NZBGet**: Usenet download client (runs only through VPN)

### 2. Media Management Stack (arr-stack.yml)

This stack handles media automation and organization:

- **Sonarr**: TV show management and automation
- **Radarr**: Movie management and automation
- **Lidarr**: Music management and automation
- **Bazarr**: Subtitle management for TV shows and movies
- **Prowlarr**: Unified indexer manager that integrates with other services
- **Flaresolverr**: Helper service to bypass Cloudflare and other protection systems

### 3. Media Server Stack (jelly-stack.yml)

This stack provides the user-facing media server:

- **Jellyfin**: Media server for streaming your media collection
- **Jellyseerr**: User request platform for media content

---

## Deployment Steps

1. **Clone the Repository**:
   ```bash
   git clone <repository-url>
   cd /path/to/your/media-server
   ```

2. **Update the `.env` File**:
   - Open the `.env` file and fill in all required values.

3. **Start the Stacks**:
   
   You can start all stacks at once:
   ```bash
   docker-compose -f media-download.yml -f arr-stack.yml -f jelly-stack.yml up -d
   ```
   
   Or start them individually as needed:
   ```bash
   # Start just the download stack
   docker-compose -f media-download.yml up -d
   
   # Start just the media management stack
   docker-compose -f arr-stack.yml up -d
   
   # Start just the Jellyfin server stack
   docker-compose -f jelly-stack.yml up -d
   ```

4. **Verify Services**:
   - Run `docker ps` to ensure all containers are running.
   - Access the services via their respective ports:
     - Jellyfin: `http://<IP_ADDR>:8096` (or via host network)
     - Jellyseerr: `http://<IP_ADDR>:5055`
     - qBittorrent: `http://<IP_ADDR>:8080`
     - NZBGet: `http://<IP_ADDR>:6789`
     - Sonarr: `http://<IP_ADDR>:8989`
     - Radarr: `http://<IP_ADDR>:7878`
     - Lidarr: `http://<IP_ADDR>:8686`
     - Bazarr: `http://<IP_ADDR>:6767`
     - Prowlarr: `http://<IP_ADDR>:9696`
     - Flaresolverr: `http://<IP_ADDR>:8191`

---

## Testing the VPN Tunnel

1. **Access the qBittorrent Web UI**:
   - Navigate to `http://<IP_ADDR>:8080`.
   
2. **Download a Test Torrent**:
   - Add a public domain torrent (e.g., a Linux ISO) to qBittorrent.
   
3. **Verify VPN Usage**:
   - Check the IP address used for downloading:
     ```bash
     docker exec -it gluetun curl ifconfig.me
     ```
   - Ensure the IP address matches your VPN provider's IP and differs from your public IP.

---

## Setting Up Indexers

1. **Access Prowlarr**:
   - Navigate to `http://<IP_ADDR>:9696`.
   
2. **Add Indexers**:
   - Go to the "Indexers" tab and click "Add Indexer."
   - Select your preferred indexer (e.g., 1337x, RARBG).
   - Configure the indexer with your credentials (if required).
   
3. **Link Prowlarr to Sonarr, Radarr, and Lidarr**:
   - In Prowlarr, go to "Apps" and add each service.
   - Provide the URLs and API keys for each service.

---

## Configuring Media Management Services

### Sonarr (TV Shows)
- Navigate to `http://<IP_ADDR>:8989`.
- Add your TV show library under "Settings > Media Management."
- Configure download clients:
  - Go to "Settings > Download Clients."
  - Add qBittorrent with the URL `http://gluetun:8080`.
  - Add NZBGet with the URL `http://gluetun:6789`.

### Radarr (Movies)
- Navigate to `http://<IP_ADDR>:7878`.
- Add your movie library under "Settings > Media Management."
- Configure download clients:
  - Go to "Settings > Download Clients."
  - Add qBittorrent with the URL `http://gluetun:8080`.
  - Add NZBGet with the URL `http://gluetun:6789`.

### Lidarr (Music)
- Navigate to `http://<IP_ADDR>:8686`.
- Add your music library under "Settings > Media Management."
- Configure download clients:
  - Go to "Settings > Download Clients."
  - Add qBittorrent with the URL `http://gluetun:8080`.
  - Add NZBGet with the URL `http://gluetun:6789`.

### Bazarr (Subtitles)
- Navigate to `http://<IP_ADDR>:6767`.
- Connect to your Sonarr and Radarr instances under "Settings".
- Configure the subtitle providers you want to use.

---

## Setting Up Jellyfin and Jellyseerr

### Jellyfin
- Navigate to Jellyfin's web UI.
- Follow the setup wizard to create an admin user.
- Add media libraries pointing to your media folders.
- Configure hardware acceleration if available.

### Jellyseerr
- Navigate to `http://<IP_ADDR>:5055`.
- Connect Jellyseerr to your Jellyfin instance.
- Configure Sonarr and Radarr connections to allow request fulfillment.

---

## Troubleshooting

- **Containers Not Starting**:
  - Check logs with `docker logs <container_name>`.
  
- **VPN Issues**:
  - Verify VPN credentials in the `.env` file.
  - Check Gluetun logs: `docker logs gluetun`.
  
- **Download Clients Can't Connect**:
  - Ensure qBittorrent and NZBGet are configured to use `gluetun` as their network.
  - Verify Gluetun is healthy: `docker ps` (should show "healthy" status).
  
- **Indexers Not Working**:
  - Ensure Flaresolverr is running for indexers like 1337x.
  - Verify indexer credentials in Prowlarr.
  
- **Cross-Service Communication**:
  - Make sure services can communicate with each other using container names as hostnames.

---

## Maintenance

- **Updating Containers**:
  ```bash
  # Pull latest images
  docker-compose -f media-download.yml -f arr-stack.yml -f jelly-stack.yml pull
  
  # Restart services with new images
  docker-compose -f media-download.yml -f arr-stack.yml -f jelly-stack.yml up -d
  ```

- **Backing Up Configurations**:
  - All service configurations are stored in the volumes you've mapped in the `.env` file.
  - To backup, create archives of these directories.

This modular approach to the media server allows you to update, restart, or troubleshoot individual components without affecting the entire system. For example, you can restart just the download stack if your VPN connection has issues, without disrupting users who are actively streaming from Jellyfin.
