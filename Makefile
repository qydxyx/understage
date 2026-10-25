.PHONY: all gen build test run cli install dist clean

SCHEME := Understage
CLI_SCHEME := understage
DEST := platform=macOS,arch=arm64
DERIVED := .derived
PREFIX ?= /usr/local

all: gen build test

gen:
	xcodegen generate --spec project.yml

build: gen
	xcodebuild -scheme $(SCHEME) -configuration Debug -destination '$(DEST)' -derivedDataPath $(DERIVED) -quiet build

test: gen
	xcodebuild test -scheme $(SCHEME) -destination '$(DEST)' -derivedDataPath $(DERIVED) -quiet

run: build
	open "$(DERIVED)/Build/Products/Debug/Understage.app"

cli: gen
	xcodebuild -scheme $(CLI_SCHEME) -configuration Release -destination '$(DEST)' -derivedDataPath $(DERIVED) -quiet build

install: cli
	install -d "$(PREFIX)/bin"
	install -m 755 "$(DERIVED)/Build/Products/Release/understage" "$(PREFIX)/bin/understage"

dist: gen
	xcodebuild -scheme $(SCHEME) -configuration Release -destination '$(DEST)' -derivedDataPath $(DERIVED) -quiet build
	xcodebuild -scheme $(CLI_SCHEME) -configuration Release -destination '$(DEST)' -derivedDataPath $(DERIVED) -quiet build
	@echo "App: $(DERIVED)/Build/Products/Release/Understage.app"
	@echo "CLI: $(DERIVED)/Build/Products/Release/understage"

clean:
	rm -rf $(DERIVED) Understage.xcodeproj
