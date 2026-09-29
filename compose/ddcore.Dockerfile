# The published ddcore image plus the bench app. DDCORE_VERSION picks the release.
ARG DDCORE_VERSION=0.21.10
FROM ghcr.io/jrvidotti/ddcore:${DDCORE_VERSION}
COPY apps/ddcore /app/apps/benchapp
COPY compose/ddcore.json /app/ddcore.json
