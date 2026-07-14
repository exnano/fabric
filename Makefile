.PHONY: build test app run distribute security-audit clean

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh

run:
	./scripts/run-app.sh

distribute:
	./scripts/distribute-app.sh

security-audit:
	./scripts/security-audit.sh

clean:
	swift package clean
	rm -rf dist
