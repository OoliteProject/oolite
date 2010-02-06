# Conveniently, this here xcconfig file declares the version in a make-compatible format.
OOLITE_VERSION_FILE = ../src/Cocoa/oolite-version.xcconfig
include $(OOLITE_VERSION_FILE)

TARGET = Basic-debug.oxp


$(TARGET): Resources/debugConfig.plist Resources/DebugOXPLocatorBeacon.magic Resources/oolite-debug-console.js requires.plist
	rm -rf $(TARGET)
	mkdir $(TARGET)
	mkdir $(TARGET)/Config
	mkdir $(TARGET)/Scripts
	cp Resources/debugConfig.plist $(TARGET)/Config/
	cp Resources/DebugOXPLocatorBeacon.magic $(TARGET)/
	cp Resources/oolite-debug-console.js $(TARGET)/Scripts/
	cp requires.plist $(TARGET)/
	
requires.plist: $(OOLITE_VERSION_FILE)
	echo "{ version = \"$(OOLITE_VERSION)\"; max_version = \"$(OOLITE_VERSION).99\"; }" > $@

clean:
	rm -rf $(TARGET)
	rm -rf requires.plist
