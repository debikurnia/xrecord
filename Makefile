# xrecord — build & test helpers
#
# Swift Testing ships inside the Command Line Tools but is not on the default
# search paths when full Xcode is absent. We resolve its location from the
# active developer dir and pass the framework search path + rpaths to `swift test`.
# If you later install full Xcode, plain `swift test` will also work.

DEVDIR := $(shell xcode-select -p)
TESTING_FRAMEWORKS := $(DEVDIR)/Library/Developer/Frameworks
TESTING_LIB := $(DEVDIR)/Library/Developer/usr/lib

TEST_FLAGS := \
	-Xswiftc -F -Xswiftc "$(TESTING_FRAMEWORKS)" \
	-Xlinker -F -Xlinker "$(TESTING_FRAMEWORKS)" \
	-Xlinker -rpath -Xlinker "$(TESTING_FRAMEWORKS)" \
	-Xlinker -rpath -Xlinker "$(TESTING_LIB)"

.PHONY: build test release clean record render

build:
	swift build

test:
	swift test $(TEST_FLAGS)

release:
	swift build -c release

# Shortcuts. Pass extra arguments via ARGS, e.g.:
#   make record ARGS="--duration 30"
#   make render ARGS="recording-20260629-103111 --zoom 2.0"
record:
	swift run -c release xrecord record $(ARGS)

render:
	swift run -c release xrecord render $(ARGS)

clean:
	rm -rf .build
