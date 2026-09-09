# Build stage
FROM golang:1.25.14-alpine3.23 AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Commit déployé, injecté dans le binaire pour que GET /health puisse le
# rapporter (détection de dérive prod ↔ main, cf. #341). Vaut "unknown" si le
# build arg n'est pas fourni — un binaire anonyme ne prétend rien.
ARG GIT_COMMIT=unknown

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo \
    -ldflags="-w -s -X main.buildCommit=${GIT_COMMIT}" -o main .

# Final stage
FROM alpine:3.24

# Install ca-certificates for HTTPS requests
RUN apk --no-cache add ca-certificates tzdata

WORKDIR /root/

RUN addgroup -g 1000 -S arbore && adduser -u 1000 -S -G arbore arbore

# Copy binary from builder stage
WORKDIR /app
COPY --from=builder --chown=arbore:arbore /app/main ./main

USER arbore

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run the binary
CMD ["./main"]
