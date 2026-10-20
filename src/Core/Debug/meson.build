# Generated Meson configuration for sub-module: Debug

oolite_sources += files(
    'OODebugMonitor.m',
    'OODebugStandards.m',
    'OODebugSupport.m',
    'OODebugTCPConsoleClient.m',
    'OOTCPStreamDecoder.c',
    'OOTCPStreamDecoderAbstractionLayer.m',
)

# TODO (port, phase 4): debug console. The JS console object is not yet
# ported to QuickJS.
if not use_quickjs
    oolite_sources += files('OOJSConsole.m')
endif

oolite_includes += include_directories('.')
