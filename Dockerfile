# ============================================================================
# [STAGE A] - Build Astro and Precompress Static Assets
# ============================================================================
FROM --platform=linux/amd64 node:22-alpine AS astro-builder

# Enable corepack for pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

WORKDIR /app/astro

# Copy dependency files first for better layer caching
COPY website/astro/package.json website/astro/pnpm-lock.yaml ./

# Install dependencies
RUN pnpm install --frozen-lockfile

# Copy config files
COPY website/astro/astro.config.mjs website/astro/tsconfig.json website/astro/tailwind.config.mjs website/astro/postcss.config.cjs ./

# Copy source directories
COPY website/astro/src ./src
COPY website/astro/public ./public
COPY website/astro/scripts ./scripts

# Install runtime dependencies for build scripts
RUN apk add --no-cache bash curl unzip

# Build Astro site
RUN pnpm run build

# Precompress all static assets with gzip -9 and remove originals
# We keep Askama templates uncompressed (they're used for server-side rendering)
# We also keep Unity WebGL files uncompressed (Unity loader expects specific formats)
WORKDIR /app/astro/dist
RUN apk add --no-cache gzip && \
    # Compress and replace CSS, JS, JSON, SVG, XML, TXT files (except Unity WebGL files)
    find . -type f \( \
        -name "*.css" -o \
        -name "*.js" -o \
        -name "*.json" -o \
        -name "*.svg" -o \
        -name "*.xml" -o \
        -name "*.txt" \
    \) ! -path "*/assets/game/*" -exec sh -c 'gzip -9 -c "$1" > "$1.gz" && rm "$1"' _ {} \; && \
    # Compress and replace HTML files (except in askama/)
    find . -type f -name "*.html" ! -path "*/askama/*" -exec sh -c 'gzip -9 -c "$1" > "$1.gz" && rm "$1"' _ {} \; && \
    # WOFF/WOFF2 are already compressed, keep originals
    # Unity WebGL files (.wasm, .data, .loader.js, .framework.js) kept uncompressed
    echo "Precompression complete"

# ============================================================================
# [STAGE B] - Rust Base Image
# ============================================================================
FROM --platform=linux/amd64 rust:1.85-slim AS rust-base

# Install build dependencies (needed for cargo-chef and some crate dependencies)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        pkg-config \
        libssl-dev && \
    rm -rf /var/lib/apt/lists/*

RUN rustup target add x86_64-unknown-linux-gnu && \
    cargo install cargo-chef --locked

WORKDIR /app

# ============================================================================
# [STAGE C] - Cargo Chef Planner
# ============================================================================
FROM rust-base AS planner

# Copy all source files needed for cargo chef to analyze
COPY website/axum/Cargo.toml website/axum/Cargo.lock ./
COPY website/axum/src ./src

RUN cargo chef prepare --recipe-path recipe.json

# ============================================================================
# [STAGE D] - Cargo Chef Builder (Cache Dependencies)
# ============================================================================
FROM rust-base AS builder-deps

COPY --from=planner /app/recipe.json recipe.json

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    cargo chef cook --release --recipe-path recipe.json

# ============================================================================
# [STAGE E] - Build Axum Application
# ============================================================================
FROM rust-base AS builder

# Copy cached dependencies from builder-deps
COPY --from=builder-deps /app/target target
COPY --from=builder-deps /usr/local/cargo /usr/local/cargo

# Copy Astro build output (with precompressed files)
COPY --from=astro-builder /app/astro/dist /app/templates/dist

# Copy Askama templates (uncompressed, for server-side rendering)
COPY website/axum/templates/askama /app/templates/askama

# Copy Axum source code
COPY website/axum/src ./src
COPY website/axum/Cargo.toml website/axum/Cargo.lock ./

# Build the Rust binary
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    cargo build --release && \
    strip target/release/kbve-bugwars

# ============================================================================
# [STAGE F] - Chisel Ubuntu Base (Minimal Runtime)
# Rust Profile Chisel by h0lybyte and special thanks to Fernando Silva for Chisel Go core.
# ============================================================================
FROM --platform=linux/amd64 ubuntu:24.04 AS chisel-builder

RUN apt-get update && apt-get install -y wget ca-certificates

WORKDIR /tmp

# Install Go for Chisel
RUN wget https://go.dev/dl/go1.23.4.linux-amd64.tar.gz && \
    tar -xvf go1.23.4.linux-amd64.tar.gz && \
    mv go /usr/local

# Install Chisel
RUN GOBIN=/usr/local/bin/ /usr/local/go/bin/go install github.com/canonical/chisel/cmd/chisel@latest

# Create minimal rootfs with only essential libraries
# Note: No libssl3_libs needed - using rustls instead
WORKDIR /rootfs
RUN chisel cut --release ubuntu-24.04 --root /rootfs \
        base-files_base \
        base-files_release-info \
        ca-certificates_data \
        libgcc-s1_libs \
        libc6_libs \
        libstdc++6_libs \
        openssl_config

# ============================================================================
# [STAGE G] - Jemalloc
# ============================================================================
FROM --platform=linux/amd64 ubuntu:24.04 AS jemalloc

RUN apt-get update && \
    apt-get install -y --no-install-recommends libjemalloc-dev && \
    apt-get autoremove -y && \
    apt-get purge -y --auto-remove && \
    rm -rf /var/lib/apt/lists/*

# ============================================================================
# [STAGE Z] - Runtime Image (Scratch + Chisel + Jemalloc)
# ============================================================================
FROM --platform=linux/amd64 scratch AS runtime

# Copy minimal Ubuntu rootfs from Chisel
COPY --from=chisel-builder /rootfs /

# Copy jemalloc library
COPY --from=jemalloc /usr/lib/x86_64-linux-gnu/libjemalloc.so.2 /usr/lib/x86_64-linux-gnu/libjemalloc.so.2

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/target/release/kbve-bugwars /app/kbve-bugwars

# Copy Astro static files (precompressed)
COPY --from=builder /app/templates/dist /app/templates/dist

# Copy Askama templates (uncompressed)
COPY --from=builder /app/templates/askama /app/templates/askama

# Set environment variables
ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
ENV MALLOC_CONF="background_thread:true,dirty_decay_ms:10000,muzzy_decay_ms:10000,lg_tcache_max:32,oversize_threshold:4194304"
ENV HTTP_HOST=0.0.0.0
ENV HTTP_PORT=4321
ENV RUST_LOG=info

# Expose port
EXPOSE 4321

# Run the application
ENTRYPOINT ["/app/kbve-bugwars"]
