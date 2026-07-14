.PHONY: build test app run clean

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh

run:
	./scripts/run-app.sh

clean:
	swift package clean
	rm -rf dist
