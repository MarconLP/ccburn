PREFIX ?= /Applications
BIN ?= $(HOME)/.local/bin
APP := build/ccburn.app

.PHONY: app install cli snapshot clean

# Build build/ccburn.app.
app:
	scripts/build-app.sh

# Build, replace the installed app and start it.
install: app
	-pkill -f '$(PREFIX)/ccburn.app/Contents/MacOS/ccburn'
	rm -rf '$(PREFIX)/ccburn.app'
	cp -R $(APP) '$(PREFIX)/ccburn.app'
	open '$(PREFIX)/ccburn.app'

# Link the terminal command to this checkout.
cli:
	mkdir -p '$(BIN)'
	ln -sf '$(CURDIR)/ccburn' '$(BIN)/ccburn'

# Render the panel to build/snapshot.png without opening the menu bar item.
snapshot: app
	$(APP)/Contents/MacOS/ccburn --snapshot build/snapshot.png --dark

clean:
	rm -rf build app/.build
