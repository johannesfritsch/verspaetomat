# Verspätomat API: one static-ish binary. Fonts for the Typst PDF are embedded at
# compile time, migrations and fixtures too, so the runtime image needs only CA roots.
#
#   docker build -t verspaetomat-api -f backend/Dockerfile backend
#
# Build context is backend/ (see deploy/docker-compose.yml).

FROM rust:1.92-bookworm AS builder
WORKDIR /src

# Dependency layer first so code changes do not rebuild Typst and friends.
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src/bin && echo 'fn main() {}' > src/main.rs && echo 'fn main() {}' > src/bin/stellwerk.rs \
    && cargo build --release --bins 2>/dev/null || true \
    && rm -rf src

COPY . .
# Touch the sources so cargo notices them after the dummy build.
RUN find src -name '*.rs' -exec touch {} + && cargo build --release --bins

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates tzdata curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --home /app --shell /usr/sbin/nologin verspaetomat
WORKDIR /app
COPY --from=builder /src/target/release/verspaetomat-api /usr/local/bin/verspaetomat-api
COPY --from=builder /src/target/release/stellwerk /usr/local/bin/stellwerk
USER verspaetomat
ENV BIND=0.0.0.0:8080 RUST_LOG=info,tower_http=info,sqlx=warn
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s CMD curl -sf http://127.0.0.1:8080/health || exit 1
# Migrations run at start (sqlx::migrate! is embedded in the binary).
CMD ["verspaetomat-api"]
