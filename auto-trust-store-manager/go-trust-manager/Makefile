.PHONY: build clean test run all

BINARY_NAME=trust-store-manager
VERSION=1.0.0
BUILD_DIR=./build

all: clean build

build:
	@echo "Building $(BINARY_NAME)..."
	go build -o $(BINARY_NAME) -v

build-all: clean
	@echo "Building for all platforms..."
	@mkdir -p $(BUILD_DIR)
	@GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o $(BUILD_DIR)/$(BINARY_NAME)-$(VERSION)-linux-amd64
	@GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o $(BUILD_DIR)/$(BINARY_NAME)-$(VERSION)-linux-arm64
	@GOOS=windows GOARCH=amd64 go build -ldflags="-s -w" -o $(BUILD_DIR)/$(BINARY_NAME)-$(VERSION)-windows-amd64.exe
	@GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -o $(BUILD_DIR)/$(BINARY_NAME)-$(VERSION)-darwin-amd64
	@GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o $(BUILD_DIR)/$(BINARY_NAME)-$(VERSION)-darwin-arm64
	@echo "Done building for all platforms."

test:
	@echo "Running tests..."
	go test -v ./...

clean:
	@echo "Cleaning up..."
	@rm -rf $(BUILD_DIR)
	@rm -f $(BINARY_NAME)

run:
	@echo "Running $(BINARY_NAME)..."
	./$(BINARY_NAME) -v 