FROM python:3.12-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

# Toolchain for dependencies that fall back to an sdist when no wheel matches
# the platform — pynacl, curl-cffi and psycopg2 all do this on arm64, so a
# plain `pip install .` fails on a Raspberry Pi. Confined to this stage so the
# compiler never ships in the runtime image.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential libffi-dev \
 && rm -rf /var/lib/apt/lists/*

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Upgrade pip before installing dependencies (GHSA-6q48-6c7w-9gw2:
# drop the compromised eMudhra/emSign CA from pip's vendored certifi).
# Hash verified against https://pypi.org/pypi/pip/26.2.2/json
RUN python -m pip install --no-cache-dir --upgrade \
      "https://files.pythonhosted.org/packages/3f/06/3e4420302363fbb71be3c7f35ce042f54bfca330e3e66b3a2e3c4cca579f/pip-26.2.2-py3-none-any.whl#sha256=fd7f4dfa8190e014013b9f08f3e973f4e4c26ffd179a204895533a7254813a70"

WORKDIR /app

COPY pyproject.toml README.md ./
COPY src/ src/

RUN pip install --no-cache-dir .


FROM python:3.12-slim

# Run unprivileged: a container escape starts as uid 999 rather than root, and
# files written into a bind mount are not root-owned on the host.
#
# HOME stays /root on purpose. Every path the app uses is HOME-relative
# (~/.hevy2garmin, ~/.garminconnect), so keeping HOME means the volume paths in
# the README keep working exactly as before — this is not a breaking change for
# existing installs. The directory is handed to the new user instead.
RUN groupadd --system --gid 999 nonroot \
 && useradd --system --gid 999 --uid 999 --home-dir /root --no-create-home nonroot \
 && mkdir -p /root/.hevy2garmin /root/.garminconnect \
 && chown -R 999:999 /root \
 && chmod 755 /root

# Only the finished virtualenv crosses over — no build tools, no sources.
COPY --from=builder /opt/venv /opt/venv

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HOME=/root

USER nonroot
WORKDIR /app

EXPOSE 8123

# Lets `docker compose` restart policies and `docker ps` reflect real health
# rather than just "the process is alive".
HEALTHCHECK --interval=60s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8123/login', timeout=4).status < 500 else 1)"

ENTRYPOINT ["hevy2garmin"]
CMD ["status"]
