# Generated Meson configuration for sub-module: EXRSnapshotSupport

oolite_sources += files(
    'OOSaveEXRSnapshot.cpp',
)

if host_machine.system() == 'windows'
    oolite_vendored_sources += files(
        'miniz.cpp',
        'tinyexr.cpp',
    )
endif

oolite_includes += include_directories('.')

