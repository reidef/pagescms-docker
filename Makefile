IMAGE     ?= pagescms
VERSION   := $(shell sed -n 's/^ARG PAGESCMS_VERSION=//p' Dockerfile)
PLATFORMS ?= linux/amd64,linux/arm64
UPSTREAM  := https://github.com/pagescms/pagescms

.PHONY: build buildx run down version upstream-versions

## Build the image for the local platform, tagged with the upstream version.
build:
	docker build -t $(IMAGE):$(VERSION) .

## Build (and push) a multi-arch image. Requires a buildx builder and registry login.
buildx:
	docker buildx build --platform $(PLATFORMS) -t $(IMAGE):$(VERSION) --push .

## Run locally with PostgreSQL (needs .env, see .env.example).
run:
	PAGESCMS_VERSION=$(VERSION) docker compose up --build

down:
	docker compose down

## Print the packaged upstream version.
version:
	@echo $(VERSION)

## List the newest upstream release tags.
upstream-versions:
	@git ls-remote --tags --refs $(UPSTREAM) | sed 's|.*refs/tags/||' | sort -V | tail -5
