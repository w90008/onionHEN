FROM ubuntu:24.04

ARG HOST_UID=1000
ARG HOST_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/usr/local/bin:/usr/lib/llvm-18/bin:/opt/ps5-payload-sdk/bin:${PATH}" \
    PS5_PAYLOAD_SDK=/opt/ps5-payload-sdk \
    KEYSTONE_PREFIX=/usr/local \
    LLVM_CONFIG=/usr/lib/llvm-18/bin/llvm-config

# ============================================================
# Packages
# ============================================================

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash \
      build-essential \
      ca-certificates \
      clang-18 \
      cmake \
      curl \
      lld-18 \
      llvm-18 \
      make \
      nodejs \
      npm \
      meson \
      ninja-build \
      passwd \
      pkg-config \
      python3 \
      python3-pip \
      python3-pyelftools \
      socat \
      unzip \
      wget \
      xz-utils \
      libssl-dev \
      librsvg2-bin \
      git \
      autoconf \
      automake \
      libtool \
      m4 \
      gettext \
      perl \
      file \
    && ln -sf /usr/lib/llvm-18/bin/llvm-config /usr/local/bin/llvm-config \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# Source
# ============================================================

WORKDIR /workspace

COPY . /workspace

RUN find /workspace -type f \
      \( -name "*.sh" -o -name "*.bash" \) \
      -print0 \
    | xargs -0 -r sed -i 's/\r$//'

# ============================================================
# PS5 Payload SDK
#
# Use official binary SDK instead of rebuilding SDK from source.
# ============================================================

RUN set -eux; \
    mkdir -p /opt; \
    cd /tmp; \
    wget -q --show-progress \
      https://github.com/ps5-payload-dev/sdk/releases/latest/download/ps5-payload-sdk.zip \
      -O ps5-payload-sdk.zip; \
    unzip -q ps5-payload-sdk.zip -d /opt; \
    test -d /opt/ps5-payload-sdk; \
    rm -f /tmp/ps5-payload-sdk.zip

# ============================================================
# SDK information
# ============================================================

RUN set -eux; \
    echo "========================================"; \
    echo "       PS5 PAYLOAD SDK"; \
    echo "========================================"; \
    echo "SDK: ${PS5_PAYLOAD_SDK}"; \
    test -x "${PS5_PAYLOAD_SDK}/bin/prospero-cmake"; \
    test -f "${PS5_PAYLOAD_SDK}/toolchain/prospero.sh"; \
    echo "prospero-cmake: OK"; \
    echo "prospero.sh: OK"; \
    echo ""; \
    echo "Checking SDK homebrew tree..."; \
    find "${PS5_PAYLOAD_SDK}/target/user" \
      -maxdepth 4 \
      -type f \
      -print 2>/dev/null || true

# ============================================================
# PS5 SDK Homebrew
# ============================================================

RUN mkdir -p \
      "${PS5_PAYLOAD_SDK}/target/user/homebrew/include" \
      "${PS5_PAYLOAD_SDK}/target/user/homebrew/lib" \
      "${PS5_PAYLOAD_SDK}/target/user/homebrew/etc" \
      "${PS5_PAYLOAD_SDK}/target/user/homebrew/share"

# ============================================================
# Locate libcurl from SDK / prebuilt dependencies
# ============================================================

RUN set -eux; \
    echo "========================================"; \
    echo "       SEARCHING FOR PS5 LIBCURL"; \
    echo "========================================"; \
    \
    find "${PS5_PAYLOAD_SDK}" \
      -type f \
      \( \
        -name "libcurl.a" \
        -o -name "curl.h" \
        -o -name "ca-bundle.crt" \
        -o -name "cacert.pem" \
      \) \
      -print || true

# ============================================================
# If curl exists somewhere inside SDK, stage it into the
# exact location required by onionHEN.
# ============================================================

RUN set -eux; \
    CURL_LIB="$(find "${PS5_PAYLOAD_SDK}" -type f -name 'libcurl.a' | head -n 1 || true)"; \
    CURL_HEADER="$(find "${PS5_PAYLOAD_SDK}" -type f -path '*/include/curl/curl.h' | head -n 1 || true)"; \
    \
    echo "CURL_LIB=${CURL_LIB}"; \
    echo "CURL_HEADER=${CURL_HEADER}"; \
    \
    if [ -n "${CURL_LIB}" ] && [ -n "${CURL_HEADER}" ]; then \
        CURL_INCLUDE="$(dirname "$(dirname "${CURL_HEADER}")")"; \
        \
        mkdir -p \
          "${PS5_PAYLOAD_SDK}/target/user/homebrew/lib" \
          "${PS5_PAYLOAD_SDK}/target/user/homebrew/include"; \
        \
        cp -f \
          "${CURL_LIB}" \
          "${PS5_PAYLOAD_SDK}/target/user/homebrew/lib/libcurl.a"; \
        \
        cp -a \
          "${CURL_INCLUDE}/curl" \
          "${PS5_PAYLOAD_SDK}/target/user/homebrew/include/"; \
    fi

# ============================================================
# CA bundle
# ============================================================

RUN set -eux; \
    mkdir -p \
      "${PS5_PAYLOAD_SDK}/target/user/homebrew/etc" \
      "${PS5_PAYLOAD_SDK}/target/user/homebrew/share"; \
    \
    if find "${PS5_PAYLOAD_SDK}" \
        -type f \
        \( -name "ca-bundle.crt" -o -name "cacert.pem" \) \
        | grep -q .; then \
        \
        CA_FILE="$(find "${PS5_PAYLOAD_SDK}" \
          -type f \
          \( -name "ca-bundle.crt" -o -name "cacert.pem" \) \
          | head -n 1)"; \
        \
        cp -f "${CA_FILE}" \
          "${PS5_PAYLOAD_SDK}/target/user/homebrew/etc/ca-bundle.crt"; \
    else \
        curl -fsSL --retry 5 \
          https://curl.se/ca/cacert.pem \
          -o "${PS5_PAYLOAD_SDK}/target/user/homebrew/etc/ca-bundle.crt"; \
    fi; \
    \
    cp -f \
      "${PS5_PAYLOAD_SDK}/target/user/homebrew/etc/ca-bundle.crt" \
      "${PS5_PAYLOAD_SDK}/target/user/homebrew/share/ca-bundle.crt"

# ============================================================
# Verify dependencies required by onionHEN
# ============================================================

RUN set -eux; \
    echo "========================================"; \
    echo "       ONIONHEN CURL CHECK"; \
    echo "========================================"; \
    \
    test -f \
      "${PS5_PAYLOAD_SDK}/target/user/homebrew/lib/libcurl.a"; \
    \
    test -f \
      "${PS5_PAYLOAD_SDK}/target/user/homebrew/include/curl/curl.h"; \
    \
    test -f \
      "${PS5_PAYLOAD_SDK}/target/user/homebrew/etc/ca-bundle.crt"; \
    \
    echo "libcurl.a: OK"; \
    echo "curl.h: OK"; \
    echo "CA bundle: OK"; \
    \
    ls -lh \
      "${PS5_PAYLOAD_SDK}/target/user/homebrew/lib/libcurl.a"; \
    \
    find \
      "${PS5_PAYLOAD_SDK}/target/user/homebrew/include/curl" \
      -maxdepth 1 \
      -type f \
      -print

# ============================================================
# Keystone
# ============================================================

RUN pip3 install \
      --break-system-packages \
      --no-cache-dir \
      keystone-engine \
    && KSO=$(python3 -c \
      'import keystone, os; print(os.path.join(os.path.dirname(keystone.__file__), "libkeystone.so"))') \
    && ln -sf "$KSO" /usr/local/lib/libkeystone.so \
    && ln -sf "$KSO" /usr/local/lib/libkeystone.so.0 \
    && ldconfig

# ============================================================
# Builder user
# ============================================================

RUN if getent group "${HOST_GID}" >/dev/null; then \
        builder_group="$(getent group "${HOST_GID}" | cut -d: -f1)"; \
    else \
        groupadd --gid "${HOST_GID}" builder; \
        builder_group=builder; \
    fi \
    && existing_user="$(getent passwd "${HOST_UID}" | cut -d: -f1 || true)" \
    && if [ -n "${existing_user}" ] && [ "${existing_user}" != "builder" ]; then \
        usermod --login builder "${existing_user}" \
        && usermod --home /home/builder --move-home builder; \
    elif ! id builder >/dev/null 2>&1; then \
        useradd \
          --uid "${HOST_UID}" \
          --gid "${HOST_GID}" \
          --create-home \
          --shell /bin/bash \
          builder; \
    fi \
    && usermod --gid "${HOST_GID}" --shell /bin/bash builder \
    && chown -R builder:"${builder_group}" /workspace

USER builder

# ============================================================
# Build onionHEN
# ============================================================

CMD ["/bin/bash", "-lc", "\
set -euo pipefail; \
rm -rf /tmp/onionhen-build; \
cp -a /workspace/. /tmp/onionhen-build; \
python3 -c \"from pathlib import Path; files=list(Path('/tmp/onionhen-build').rglob('*.sh'))+list(Path('/tmp/onionhen-build').rglob('*.bash')); [p.write_bytes(p.read_bytes().replace(bytes([13]), bytes())) for p in files]\"; \
cd /tmp/onionhen-build; \
export PS5_PAYLOAD_SDK=/opt/ps5-payload-sdk; \
export PATH=/usr/lib/llvm-18/bin:${PS5_PAYLOAD_SDK}/bin:${PATH}; \
export LLVM_CONFIG=/usr/lib/llvm-18/bin/llvm-config; \
echo '========================================'; \
echo '          onionHEN BUILD'; \
echo '========================================'; \
echo ''; \
echo 'Checking libcurl...'; \
test -f \"${PS5_PAYLOAD_SDK}/target/user/homebrew/lib/libcurl.a\"; \
echo 'libcurl OK'; \
echo ''; \
echo 'Checking curl headers...'; \
test -f \"${PS5_PAYLOAD_SDK}/target/user/homebrew/include/curl/curl.h\"; \
echo 'curl headers OK'; \
echo ''; \
echo 'Checking CA bundle...'; \
test -f \"${PS5_PAYLOAD_SDK}/target/user/homebrew/etc/ca-bundle.crt\"; \
echo 'CA bundle OK'; \
echo ''; \
echo 'Dependencies OK'; \
echo ''; \
./scripts/build.sh --jobs 8 --release; \
echo ''; \
echo '========================================'; \
echo '          BUILD FINISHED'; \
echo '========================================'; \
rm -rf /workspace/build; \
cp -a /tmp/onionhen-build/build /workspace/build; \
find /workspace/build/bin -maxdepth 1 -type f -print \
"]
