"""Offline proof that tests/source_paths.py resolves a source by stem and never guesses (oo-7j3t).

The GUI and golden tiers open engine sources through it, so a resolver that quietly picked one of
two copies, or returned a path that does not exist, would turn every source-text guard that uses
it into a check against the wrong bytes.
"""

import os
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
TESTS_DIR = os.path.abspath(os.path.join(HERE, ".."))
if TESTS_DIR not in sys.path:
    sys.path.insert(0, TESTS_DIR)

import source_paths  # noqa: E402


@pytest.mark.offline
def test_a_real_stem_resolves_to_the_one_file_the_tree_has():
    path = source_paths.resolve_source("Core", "Entities", "PlayerEntity")
    assert os.path.isfile(path)
    assert os.path.splitext(path)[1] in source_paths.IMPLEMENTATION_SUFFIXES
    # A name written against an older suffix resolves to the same file.
    assert source_paths.resolve_source("Core", "Entities", "PlayerEntity.m") == path


@pytest.mark.offline
def test_a_missing_stem_is_an_error_naming_every_candidate(tmp_path):
    with pytest.raises(FileNotFoundError) as info:
        source_paths.resolve_source(str(tmp_path), "Nowhere")
    for suffix in source_paths.IMPLEMENTATION_SUFFIXES:
        assert "Nowhere" + suffix in str(info.value)


@pytest.mark.offline
def test_two_copies_of_one_stem_are_refused_not_picked(tmp_path):
    (tmp_path / "Thing.m").write_text("old\n")
    (tmp_path / "Thing.mm").write_text("new\n")
    with pytest.raises(LookupError):
        source_paths.resolve_source(str(tmp_path), "Thing")


@pytest.mark.offline
def test_a_tree_scan_reads_every_implementation_language(tmp_path):
    for name in ("a.m", "b.mm", "c.cpp", "d.c", "e.h", "f.hpp", "g.txt"):
        (tmp_path / name).write_text("x\n")
    found = [os.path.basename(p) for p in source_paths.iter_source_files(str(tmp_path))]
    assert found == ["a.m", "b.mm", "c.cpp", "d.c", "e.h", "f.hpp"]


@pytest.mark.offline
def test_a_stem_ignores_the_implementation_suffix_but_not_a_header():
    assert source_paths.source_stem("SDL\\MyOpenGLView.mm") == "SDL/MyOpenGLView"
    assert source_paths.source_stem("SDL/MyOpenGLView.m") == "SDL/MyOpenGLView"
    assert source_paths.source_stem("SDL/MyOpenGLView.h") == "SDL/MyOpenGLView.h"
