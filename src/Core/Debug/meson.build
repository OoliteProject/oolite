# Generated Meson configuration for sub-module: Debug

oolite_sources += files(
    'OODebugMonitor.m',
    'OODebugStandards.m',
    'OODebugSupport.m',
    'OODebugTCPConsoleClient.m',
    'OOTCPStreamDecoder.c',
    'OOTCPStreamDecoderAbstractionLayer.m',
)

if use_quickjs
    oolite_sources += files('QuickJS/OOJSConsole.m')
else
    oolite_sources += files('OOJSConsole.m')
endif

oolite_includes += include_directories('.')
