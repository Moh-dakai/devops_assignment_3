# =============================================================================
# Dockerfile — DevOps CI Tool
# Base: Alpine Linux 3.19
# =============================================================================

FROM alpine:3.19

# Install required tools:
#   bash          — required for the app.sh scripts
#   curl          — HTTP utility
#   bind-tools    — dig, nslookup, host for DNS resolution
#   netcat-openbsd — nc for TCP port checking
#   iputils       — ping
#   procps        — uptime, ps, free
RUN apk add --no-cache \
    bash \
    curl \
    bind-tools \
    netcat-openbsd \
    iputils \
    procps

# Copy application source into image
COPY app/ /app/app/

# Set working directory
WORKDIR /app

# Make the entrypoint executable
RUN chmod +x /app/app/app.sh

# Default entrypoint is the app script; default argument is 'help'
ENTRYPOINT ["./app/app.sh"]
CMD ["help"]
