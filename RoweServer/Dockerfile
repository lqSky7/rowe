# syntax=docker/dockerfile:1
FROM golang:1.24-alpine AS builder
RUN apk add --no-cache gcc musl-dev sqlite-dev
WORKDIR /src
COPY go.mod ./
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=1 go build -ldflags="-s -w" -o /out/rowe-server ./cmd/server

FROM alpine:3.21
RUN apk add --no-cache ca-certificates sqlite-libs && \
    adduser -D -H -u 10001 rowe
WORKDIR /app
COPY --from=builder /out/rowe-server /app/rowe-server
RUN mkdir -p /data && chown -R rowe:rowe /data
USER rowe
ENV ROWE_ADDR=:8080
ENV ROWE_DB_PATH=/data/rowe.db
EXPOSE 8080
VOLUME ["/data"]
ENTRYPOINT ["/app/rowe-server"]
