# Use Ubuntu 24.04 as base
FROM ubuntu:24.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install basic dependencies and developer tools
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    build-essential \
    ca-certificates \
    ripgrep \
    fd-find \
    jq \
    tree \
    htop \
    vim \
    less \
    && rm -rf /var/lib/apt/lists/*

# Create symlink for fd (installed as fd-find on Ubuntu)
RUN ln -s $(which fdfind) /usr/local/bin/fd 2>/dev/null || true

# Install Julia 1.12.1 (latest stable as of 2025)
ENV JULIA_VERSION=1.12.1
ENV JULIA_PATH=/opt/julia
ENV PATH="${JULIA_PATH}/bin:${PATH}"

RUN wget -q https://julialang-s3.julialang.org/bin/linux/x64/1.12/julia-${JULIA_VERSION}-linux-x86_64.tar.gz && \
    tar -xzf julia-${JULIA_VERSION}-linux-x86_64.tar.gz && \
    mv julia-${JULIA_VERSION} ${JULIA_PATH} && \
    rm julia-${JULIA_VERSION}-linux-x86_64.tar.gz && \
    ln -s ${JULIA_PATH}/bin/julia /usr/local/bin/julia

# Pre-install common Julia packages for this project
RUN julia -e 'using Pkg; Pkg.add(["Distributions", "Random", "Logging"])'

# Set working directory
WORKDIR /workspace

# Reset frontend
ENV DEBIAN_FRONTEND=

CMD ["/bin/bash"]
