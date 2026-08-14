APP        := minrl
BUNDLE     := $(APP).app
CC         := clang
FRAMEWORKS := -framework Cocoa -framework CoreGraphics -framework ApplicationServices

COMMON  := -Wall -Wextra
DEBUG   := -O0 -g
RELEASE := -Oz -flto -fvisibility=hidden -Wl,-dead_strip

.PHONY: all debug release bundle debug-bundle icon clean

all: debug

# Loose executable (run from a terminal for live debug output).
debug:
	@$(CC) -o $(APP) main.m $(COMMON) $(DEBUG) $(FRAMEWORKS)
	@echo "Built ./$(APP)"

release:
	@$(CC) -o $(APP) main.m $(COMMON) $(RELEASE) $(FRAMEWORKS)
	@echo "Built ./$(APP) (release)"

# Generates AppIcon.icns from geticon.m.
icon:
	@$(CC) -o geticon geticon.m $(COMMON) -O0 -framework Cocoa
	@./geticon AppIcon.iconset >/dev/null
	@iconutil -c icns AppIcon.iconset -o AppIcon.icns
	@rm -rf AppIcon.iconset geticon
	@echo "Generated AppIcon.icns"

# .app bundles.
bundle: icon
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	@cp Info.plist $(BUNDLE)/Contents/Info.plist
	@cp AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	@$(CC) -o $(BUNDLE)/Contents/MacOS/$(APP) main.m $(COMMON) $(RELEASE) $(FRAMEWORKS)
	@rm -f $(APP) diag
	@rm -rf minrl.dSYM
	@echo "Built $(BUNDLE)"

debug-bundle: icon
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	@cp Info.plist $(BUNDLE)/Contents/Info.plist
	@cp AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	@$(CC) -o $(BUNDLE)/Contents/MacOS/$(APP) main.m $(COMMON) $(DEBUG) $(FRAMEWORKS)
	@echo "Built $(BUNDLE) (debug)"

clean:
	@rm -rf $(BUNDLE) $(APP) diag geticon AppIcon.icns AppIcon.iconset minrl.dSYM
	@echo "Cleaned"
