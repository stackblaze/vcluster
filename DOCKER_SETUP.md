# Docker Installation and Setup for vCluster Build

## Summary

Docker has been successfully installed on your Debian 12 system to replace Podman for building vCluster.

## What Was Done

### 1. Docker Installation
- Added Docker's official GPG key and repository
- Installed Docker Engine (v29.0.4) and related components:
  - docker-ce
  - docker-ce-cli
  - containerd.io
  - docker-buildx-plugin
  - docker-compose-plugin

### 2. User Configuration
- Added user `linux` to the `docker` group for non-root Docker access
- **Note**: You'll need to log out and back in for group changes to take full effect

### 3. Dockerfile Fixes
- Changed Helm version from v3.17.3 (doesn't exist) to v3.16.3
- Added workaround for network connectivity issues inside Docker containers
- Pre-downloaded Helm binary on host and copy it into the image

### 4. Build Script
- Created `/home/linux/vcluster/test/build-with-docker.sh`
- This script builds vCluster using Docker instead of Podman
- Automatically detects architecture and uses sudo if needed

## Usage

### Building vCluster

```bash
cd /home/linux/vcluster/test
./build-with-docker.sh
```

This will create an image: `vcluster-custom:connector-test`

### Checking Docker Status

```bash
# Check Docker service
sudo systemctl status docker

# List Docker images
docker images

# Test Docker (after logging out/in)
docker run hello-world
```

### Loading Image to Kubernetes

#### For kind:
```bash
kind create cluster --name vcluster-test
docker save vcluster-custom:connector-test | kind load image-archive /dev/stdin --name vcluster-test
```

#### For minikube:
```bash
minikube start
docker save vcluster-custom:connector-test -o /tmp/vcluster.tar
minikube image load /tmp/vcluster.tar
```

## Important Notes

1. **Group Membership**: After adding your user to the docker group, you need to:
   - Log out and log back in, OR
   - Run `newgrp docker` in your current shell, OR
   - Use `sudo docker` until you log out/in

2. **Network Issues**: If you encounter network issues during build:
   - The Helm binary is pre-downloaded on the host to work around this
   - Make sure `/tmp/linux-amd64/helm` exists before building

3. **Build Cache**: Docker uses layer caching. To force a clean build:
   ```bash
   sudo docker build --no-cache ...
   ```

## Troubleshooting

### Permission Denied
```bash
# If you get permission denied:
sudo docker <command>

# Or log out and back in for group changes
```

### Network Issues
```bash
# Check Docker network
sudo docker network ls

# Restart Docker service
sudo systemctl restart docker
```

### Clean Up Old Images
```bash
# Remove unused images
docker image prune -a

# Remove specific image
docker rmi vcluster-custom:connector-test
```

## Files Modified

- `/home/linux/vcluster/Dockerfile` - Fixed Helm version and added workaround
- `/home/linux/vcluster/test/build-with-docker.sh` - New Docker build script

## Next Steps

1. Wait for the current build to complete
2. Check the build output in the terminal
3. Once built, load the image to your Kubernetes cluster
4. Deploy vCluster with your custom connector changes

## Git Commit Message

```
feat: install Docker and fix build issues

- Install Docker Engine v29.0.4 on Debian 12
- Fix Helm version in Dockerfile (v3.17.3 → v3.16.3)
- Add workaround for network issues in Docker build
- Create Docker-based build script
- Add user to docker group for non-root access
```

