# Ubuntu as the base image
FROM ubuntu:22.04

# Build arguments
ARG WARP_VERSION
ARG GOST_VERSION
ARG COMMIT_SHA
ARG TARGETPLATFORM

# Metadata labels
LABEL org.opencontainers.image.authors="miraz4300"
LABEL org.opencontainers.image.url="https://github.com/miraz4300/wormhole"
LABEL WARP_VERSION=${WARP_VERSION}
LABEL GOST_VERSION=${GOST_VERSION}
LABEL COMMIT_SHA=${COMMIT_SHA}

# Copy scripts into the container
COPY entrypoint.sh /entrypoint.sh
COPY ./healthcheck /healthcheck

# Install dependencies
RUN case ${TARGETPLATFORM} in \
      "linux/amd64")   export ARCH="amd64" ;; \
      "linux/arm64")   export ARCH="armv8" ;; \
      *) echo "Unsupported TARGETPLATFORM: ${TARGETPLATFORM}" && exit 1 ;; \
    esac && \
    echo "Building for ${ARCH} with GOST ${GOST_VERSION}" && \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y ca-certificates curl gnupg lsb-release sudo jq ipcalc wget iptables supervisor && \
    rm -rf /var/lib/apt/list/* && \
    update-alternatives --set iptables /usr/sbin/iptables-legacy && \
    curl https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update && \
    apt-get install -y cloudflare-warp && \
    apt-get clean && \
    apt-get autoremove -y && \
    curl -LO https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/gost-linux-${ARCH}-${GOST_VERSION}.gz && \
    gunzip gost-linux-${ARCH}-${GOST_VERSION}.gz && \
    mv gost-linux-${ARCH}-${GOST_VERSION} /usr/bin/gost && \
    chmod +x /usr/bin/gost && \
    chmod +x /entrypoint.sh && \
    chmod +x /healthcheck/index.sh && \
    useradd -m -s /bin/bash warp && \
    echo "warp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/warp

# Switch to the warp user
USER warp

# Accept Cloudflare WARP TOS
RUN mkdir -p /home/warp/.local/share/warp && \
    echo -n 'yes' > /home/warp/.local/share/warp/accepted-tos.txt

# Environment variables for docker
ENV DOCKER_CHANNEL=stable \
	DOCKER_VERSION=27.1.2 \
	DOCKER_COMPOSE_VERSION=v2.29.1 \
	BUILDX_VERSION=v0.16.2 \
	DEBUG=false

# Docker and buildx installation
RUN set -eux; \
	\
	arch="$(uname -m)"; \
	case "$arch" in \
        # amd64
		x86_64) dockerArch='x86_64' ; buildx_arch='linux-amd64' ;; \
        # arm32v6
		armhf) dockerArch='armel' ; buildx_arch='linux-arm-v6' ;; \
        # arm32v7
		armv7) dockerArch='armhf' ; buildx_arch='linux-arm-v7' ;; \
        # arm64v8
		aarch64) dockerArch='aarch64' ; buildx_arch='linux-arm64' ;; \
		*) echo >&2 "error: unsupported architecture ($arch)"; exit 1 ;;\
	esac; \
	\
	if ! wget -O docker.tgz "https://download.docker.com/linux/static/${DOCKER_CHANNEL}/${dockerArch}/docker-${DOCKER_VERSION}.tgz"; then \
		echo >&2 "error: failed to download 'docker-${DOCKER_VERSION}' from '${DOCKER_CHANNEL}' for '${dockerArch}'"; \
		exit 1; \
	fi; \
	\
	tar --extract \
		--file docker.tgz \
		--strip-components 1 \
		--directory /usr/local/bin/ \
	; \
	rm docker.tgz; \
	if ! wget -O docker-buildx "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.${buildx_arch}"; then \
		echo >&2 "error: failed to download 'buildx-${BUILDX_VERSION}.${buildx_arch}'"; \
		exit 1; \
	fi; \
	mkdir -p /usr/local/lib/docker/cli-plugins; \
	chmod +x docker-buildx; \
	mv docker-buildx /usr/local/lib/docker/cli-plugins/docker-buildx; \
	\
	dockerd --version; \
	docker --version; \
	docker buildx version

# Copy scripts and configuration files
COPY modprobe start-docker.sh entrypoint-dind.sh /usr/local/bin/
COPY supervisor/ /etc/supervisor/conf.d/
COPY logger.sh /opt/bash-utils/logger.sh

# Set permissions for scripts
RUN chmod +x /usr/local/bin/start-docker.sh \
	/usr/local/bin/entrypoint.sh \
	/usr/local/bin/modprobe

VOLUME /var/lib/docker

# Docker compose installation
RUN curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose \
	&& chmod +x /usr/local/bin/docker-compose && docker-compose version

# Create a symlink to the docker binary in /usr/local/lib/docker/cli-plugins
# for users which uses 'docker compose' instead of 'docker-compose'
RUN ln -s /usr/local/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose

# Environment variables
ENV GOST_ARGS="-L :1080"
ENV WARP_SLEEP=2

# Healthcheck command
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD /healthcheck/index.sh

# Entry point script
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
