# Autobat Legions - Legion Draft matchmaking server (headless Godot).
# Build from the repository root:
#   docker build -f server/Dockerfile -t autobat-server .
FROM debian:bookworm-slim

# Must match the Godot version players' builds are exported with.
ARG GODOT_VERSION=4.3

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*

RUN wget -q "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip \
 && unzip -q /tmp/godot.zip -d /tmp \
 && mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
 && chmod +x /usr/local/bin/godot \
 && rm /tmp/godot.zip

RUN useradd --create-home --shell /usr/sbin/nologin godot
WORKDIR /game
COPY --chown=godot:godot . /game
USER godot

# Import assets and register script classes once at build time.
RUN godot --headless --path /game --import || true \
 && test -f /game/.godot/global_script_class_cache.cfg

ENV PORT=24702
EXPOSE 24702/udp
CMD ["godot", "--headless", "--path", "/game", "--", "--server"]
