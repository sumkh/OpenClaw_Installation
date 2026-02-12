FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl jq gnupg && \
    rm -rf /var/lib/apt/lists/*

# Create runtime user
RUN groupadd -r openclaw || true && useradd -r -g openclaw -d /opt/openclaw -s /usr/sbin/nologin openclaw || true

WORKDIR /opt/openclaw

# Copy application files (bind-mount in compose for active development)
COPY ./app /opt/openclaw/app
COPY config/ /opt/openclaw/config/

RUN chown -R openclaw:openclaw /opt/openclaw

ENV OPENCLAW_HOME=/opt/openclaw
ENV PATH=$PATH:/opt/openclaw/app

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

USER openclaw

CMD ["/opt/openclaw/app/start.sh"]
