PREFIX ?= /usr/local
BINARY := $(PREFIX)/bin/clipultra
LABEL := io.github.jkmungara.clipultra
PLIST := $(HOME)/Library/LaunchAgents/$(LABEL).plist

.PHONY: build test install uninstall start stop clean

build:
	swift build -c release
	@echo "Built .build/release/clipultra"

test:
	swift test

# Copies the binary and starts it at every login (launchd). Edit the plist's ProgramArguments to
# pass options such as --max-width or --save-dir.
install: build
	install -d $(PREFIX)/bin
	install -m 755 .build/release/clipultra $(BINARY)
	mkdir -p $(HOME)/Library/LaunchAgents
	sed -e 's|@BINARY@|$(BINARY)|' -e 's|@HOME@|$(HOME)|g' support/$(LABEL).plist.template > $(PLIST)
	launchctl bootout gui/$$(id -u)/$(LABEL) 2>/dev/null || true
	launchctl bootstrap gui/$$(id -u) $(PLIST)
	@echo "Installed $(BINARY); running now and at every login. Log: ~/Library/Logs/clipultra.log"

uninstall:
	launchctl bootout gui/$$(id -u)/$(LABEL) 2>/dev/null || true
	rm -f $(PLIST) $(BINARY)
	@echo "Removed clipultra"

stop:
	launchctl bootout gui/$$(id -u)/$(LABEL)

start:
	launchctl bootstrap gui/$$(id -u) $(PLIST)

clean:
	rm -rf .build
