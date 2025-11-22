# Signet Lightning Node on Nix (Docker)

Signet Lightning Node stack (Trustedcoin + Core lightning + LNBits) built on top of Nix and NixOS devShell using flakes.

## Prerequisites

- Docker and Docker Compose installed

## Quick Start

### 1. Initial Setup

```bash
# Build and start container
docker-compose up -d --build
```

### 2. Enter Container

```bash
docker exec -it lightning-node-container bash
```

### 3. Run dev shell

```bash
cd lightning-node-flake/

nix develop
```

### 4. Setup Lightning node environment

```bash
setup-lightning-env
```

### 5. Start Services

```bash
lightning-start
```

### 6. Check Services Status

```bash
lightning-status
```

### 7. Access LNBits

Open your browser to: http://localhost:8080


## Troubleshooting

### Services won't start
```bash
# Check logs
lightning-logs

# Or check individual logs
lightning-logs lightningd
lightning-logs lnbits
lightning-logs caddy
lightning-logs supervisor
```

### Port conflicts
Make sure ports 8080, 5000 aren't in use on your host:
```bash
# On host machine
lsof -i :8080
lsof -i :5000
```

### Reset everything
```bash
# Stop container
docker-compose down

# Remove volumes (WARNING: deletes all data)
docker-compose down -v

# Rebuild
docker-compose up -d --build
```

## File Locations (Inside Container)

- **Flake**: `$HOME/lightning-node-flake/flake.nix`
- **Lightning data**: `$HOME/.lightning-node/.lightning/signet/`
- **LNbits**: `$HOME/.lightning-node/lnbits/`
- **LNbits data**: `$HOME/.lightning-node/lnbits/data`

## Cleanup

```bash
# Stop and remove container
docker-compose down

# Remove all data
docker-compose down -v

# Remove images
docker rmi lightning-node-container
```

## Caddy (hosted on a VPS)

This project includes a Caddy configuration for serving LNBits behind a reverse proxy. To deploy LNBits securely on your VPS, you need to modify the Caddyfile to include your own domain.

Replace port :8080 with <your-actual-domain.com> and save the Caddyfile before starting.