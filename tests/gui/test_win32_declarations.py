"""Every Win32 call in this tier must declare argtypes/restype (bug oo-x2uy).

A ctypes foreign function with no ``argtypes`` marshals a Python ``int`` argument as a 32-bit
C ``int``; with no ``restype`` it decodes the return value as a 32-bit signed ``int``. On
64-bit Windows an HWND is a pointer-sized 64-bit handle, so an undeclared call cannot carry
one. Windows usually hands out small HWNDs, which is why the tier appeared to work - the bug
is LATENT, and a test that merely calls the functions on today's handles proves nothing.

So these tests prove two separate things, and neither needs a window:

* ``test_undeclared_call_cannot_carry_a_64_bit_handle`` demonstrates the defect itself against
  a real 64-bit ctypes function pointer: the undeclared call loses (or refuses) a handle above
  2**32 that the declared call round-trips exactly.
* the AST scan below FAILS if any ``user32.``/``shcore.``/``kernel32.`` call site in this tier
  is missing from ``conftest.WIN32_SIGNATURES``, or reaches the API through ``ctypes.windll``
  (a process-wide cached library whose function objects are shared with every other importer,
  so declaring argtypes on it mutates somebody else's calls).

All offline: importable and runnable on any platform.
"""

import ast
import ctypes
import os

import pytest

import conftest

HERE = os.path.dirname(os.path.abspath(__file__))

# The libraries whose call sites must be declared. Extend this when the tier starts calling a
# new one - and then the scan below will demand the signatures too. advapi32 joined when the
# tier started reading process integrity levels to tell an elevated foreground owner from a
# broken G1 (bead oo-0p8f).
GUARDED_LIBRARIES = (
    "user32",
    "shcore",
    "kernel32",
    "advapi32",
    "USER32",
    "SHCORE",
    "KERNEL32",
    "ADVAPI32",
)

# Attributes of a library handle that are ctypes machinery rather than an API call.
_NOT_A_CALL = {"_FuncPtr", "_handle", "_name"}


def _tier_sources():
    for name in sorted(os.listdir(HERE)):
        if name.endswith(".py"):
            with open(os.path.join(HERE, name), "r", encoding="utf-8") as handle:
                yield name, ast.parse(handle.read(), filename=name)


def _library_call_sites():
    """``{(source file, library, function)}`` for every ``<lib>.<Func>(...)`` in the tier."""
    sites = set()
    for name, tree in _tier_sources():
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            func = node.func
            if not isinstance(func, ast.Attribute) or not isinstance(func.value, ast.Name):
                continue
            library = func.value.id
            if library in GUARDED_LIBRARIES and func.attr not in _NOT_A_CALL:
                sites.add((name, library.lower(), func.attr))
    return sites


@pytest.mark.offline
def test_every_win32_call_site_is_declared():
    """No call site may reach a Win32 API that WIN32_SIGNATURES does not declare."""
    sites = _library_call_sites()
    assert sites, (
        "the scan found no Win32 call sites at all in this tier - the guard has been "
        "defeated by a refactor (e.g. calls now made through a local alias) and must be "
        "taught the new shape rather than left passing vacuously"
    )
    undeclared = sorted(
        f"{name}: {library}.{function}"
        for name, library, function in sites
        if f"{library}.{function}" not in conftest.WIN32_SIGNATURES
    )
    assert not undeclared, (
        "these Win32 call sites have no argtypes/restype declaration in "
        "conftest.WIN32_SIGNATURES, so an HWND argument is marshalled as a 32-bit int and "
        "truncates on 64-bit Windows (oo-x2uy):\n  " + "\n  ".join(undeclared)
    )


@pytest.mark.offline
def test_no_call_goes_through_ctypes_windll():
    """``ctypes.windll`` is banned: its function objects are shared process-wide.

    windll caches one library object per name for the whole interpreter, so declaring
    argtypes on it would silently change the marshalling of every other importer's calls -
    and conversely, anybody else's declarations would apply to ours. The tier owns its
    handles (``ctypes.WinDLL('user32', use_last_error=True)``).
    """
    offenders = []
    for name, tree in _tier_sources():
        if name == os.path.basename(__file__):
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Attribute) and node.attr == "windll":
                offenders.append(f"{name}:{node.lineno}")
            elif (
                isinstance(node, ast.Attribute)
                and isinstance(node.value, ast.Attribute)
                and node.value.attr == "windll"
            ):
                offenders.append(f"{name}:{node.lineno}")
    assert not offenders, (
        "ctypes.windll used at " + ", ".join(sorted(set(offenders))) + "; use the tier's own "
        "WinDLL handle so argtypes are not shared with the rest of the process (oo-x2uy)"
    )


@pytest.mark.offline
def test_declarations_name_pointer_sized_handle_types():
    """HWND-taking calls must be declared HWND, not an int-ish type.

    Declaring ``c_int`` would satisfy "has argtypes" while reproducing the bug exactly.
    """
    handle_takers = (
        "user32.GetWindowThreadProcessId",
        "user32.IsWindowVisible",
        "user32.SendMessageTimeoutW",
        "user32.GetWindowRect",
        "user32.GetClientRect",
        "user32.ClientToScreen",
        "user32.SetWindowPos",
        "user32.ShowWindow",
        "user32.SetForegroundWindow",
    )
    for qualified in handle_takers:
        assert qualified in conftest.WIN32_SIGNATURES, f"{qualified} is not declared at all"
        _restype, argtypes = conftest.WIN32_SIGNATURES[qualified]
        assert argtypes and argtypes[0] == "HWND", (
            f"{qualified} takes a window handle; its first argtype is declared "
            f"{argtypes[0] if argtypes else 'nothing'!r}, which is not pointer-sized"
        )
    # SendMessageTimeoutW returns LRESULT (LONG_PTR), not a 32-bit int.
    assert conftest.WIN32_SIGNATURES["user32.SendMessageTimeoutW"][0] == "LRESULT"


@pytest.mark.offline
def test_the_process_table_calls_are_declared_with_pointer_sized_handles():
    """The Tool Help walk's kernel32 calls carry real HANDLE types, not c_void_p/c_int.

    surviving_game_processes (oo-5rsa) is the OS-level witness that no orphaned oolite.exe
    survived the exit, and it reads the process table through CreateToolhelp32Snapshot. An
    undeclared restype decodes that pointer-sized HANDLE through a 32-bit signed int; the
    truncated handle then makes Process32First fail, the table comes back empty, and the
    survivor check reports "nothing survived" - a silent pass in the very check that exists to
    remove silent passes. As with HWND, "has argtypes" is not enough: the type must be
    pointer-sized.
    """
    for qualified in (
        "kernel32.CreateToolhelp32Snapshot",
        "kernel32.Process32First",
        "kernel32.Process32Next",
        "kernel32.CloseHandle",
    ):
        assert qualified in conftest.WIN32_SIGNATURES, f"{qualified} is not declared at all"
    assert conftest.WIN32_SIGNATURES["kernel32.CreateToolhelp32Snapshot"][0] == "HANDLE", (
        "the snapshot handle is pointer-sized; a 32-bit restype truncates it"
    )
    for qualified in ("kernel32.Process32First", "kernel32.Process32Next", "kernel32.CloseHandle"):
        assert conftest.WIN32_SIGNATURES[qualified][1][0] == "HANDLE", (
            f"{qualified} takes the snapshot HANDLE as its first argument; declaring it "
            "c_void_p or c_int would satisfy 'has argtypes' while keeping the bug"
        )
    for qualified in ("kernel32.Process32First", "kernel32.Process32Next"):
        assert conftest.WIN32_SIGNATURES[qualified][1][1] == "LPPROCESSENTRY32", (
            f"{qualified} takes a PROCESSENTRY32*; a bare pointer would accept any structure, "
            "and a wrong layout makes the call return FALSE - i.e. 'no processes'"
        )


@pytest.mark.offline
@pytest.mark.skipif(not conftest.IS_WINDOWS, reason="the real kernel32 exists only on Windows")
def test_the_live_kernel32_functions_carry_the_declarations():
    """The kernel32 half of the table is stamped onto the real function objects."""
    assert conftest.KERNEL32 is not None
    assert conftest.KERNEL32 is not ctypes.windll.kernel32, (
        "the tier must own its kernel32 handle so its argtypes are not process-wide"
    )
    snapshot = conftest.KERNEL32.CreateToolhelp32Snapshot
    assert snapshot.restype is not None, "CreateToolhelp32Snapshot has no restype"
    assert ctypes.sizeof(snapshot.restype) == ctypes.sizeof(ctypes.c_void_p), (
        "CreateToolhelp32Snapshot returns a pointer-sized HANDLE; a 32-bit restype would "
        "truncate and sign-extend it"
    )
    for name in ("Process32First", "Process32Next", "CloseHandle"):
        func = getattr(conftest.KERNEL32, name)
        assert func.argtypes, f"{name} has no argtypes on the live function"
        assert ctypes.sizeof(func.argtypes[0]) == ctypes.sizeof(ctypes.c_void_p), (
            f"{name}'s handle argument is declared HANDLE but is only "
            f"{ctypes.sizeof(func.argtypes[0])} bytes wide"
        )
    # The structure pointer must be a real PROCESSENTRY32*, not an untyped pointer.
    assert conftest.PROCESSENTRY32 is not None
    entry_param = conftest.KERNEL32.Process32First.argtypes[1]
    assert getattr(entry_param, "_type_", None) is conftest.PROCESSENTRY32, (
        "Process32First's second argument must be POINTER(PROCESSENTRY32)"
    )


@pytest.mark.offline
def test_undeclared_call_cannot_carry_a_64_bit_handle():
    """The defect itself, shown on a real 64-bit foreign function pointer.

    A CFUNCTYPE callback that returns its own 64-bit argument stands in for any Win32 call
    taking an HWND. Reached through ``CDLL._FuncPtr`` it is exactly the kind of object
    ``ctypes.windll.user32.SomeCall`` is: a foreign function with no argtypes. Declared, it
    round-trips a handle above 2**32; undeclared, it does not - either OverflowError (current
    CPython refuses to narrow) or a truncated low half (older CPython narrows silently).
    Either way the tier cannot address such a window.
    """
    if ctypes.sizeof(ctypes.c_void_p) != 8:
        pytest.skip("the truncation only exists on a 64-bit build")

    identity = ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.c_uint64)(lambda value: value)
    address = ctypes.cast(identity, ctypes.c_void_p).value
    library = ctypes.CDLL(None) if os.name != "nt" else ctypes.CDLL("ucrtbase")

    undeclared = library._FuncPtr(address)
    undeclared.restype = ctypes.c_uint64  # only the ARGUMENT width is under test here

    declared = library._FuncPtr(address)
    declared.argtypes = [ctypes.c_uint64]
    declared.restype = ctypes.c_uint64

    small = 0x0001_ABCD  # the handles Windows happens to hand out today
    assert undeclared(small) == small, "small handles survive either way - hence 'latent'"
    assert declared(small) == small

    big = 0x0000_7FFD_1234_ABCD  # a perfectly legal 64-bit HWND
    assert declared(big) == big, "the declared call must carry the whole handle"

    try:
        got = undeclared(big)
    except ctypes.ArgumentError:
        pass  # CPython refuses to narrow: the call cannot be made at all
    else:
        assert got != big, (
            "expected the undeclared call to lose the high half of the handle; if this ever "
            "stops being true, ctypes has changed its default marshalling and this guard "
            "needs rewriting rather than deleting"
        )
        assert got == big & 0xFFFF_FFFF, "truncated to the low 32 bits, as documented"


@pytest.mark.offline
@pytest.mark.skipif(not conftest.IS_WINDOWS, reason="the real user32 exists only on Windows")
def test_the_live_user32_functions_carry_the_declarations():
    """The table is not decoration: it must be stamped onto the real function objects."""
    assert conftest.USER32 is not None
    for qualified, (_restype, argtypes) in conftest.WIN32_SIGNATURES.items():
        library, _, name = qualified.partition(".")
        if library != "user32":
            continue
        func = getattr(conftest.USER32, name, None)
        if func is None:
            # _declare_win32 `continue`s over an absent OPTIONAL_WIN32 entry, so on a host that
            # lacks one (SetProcessDpiAwarenessContext is absent before Windows 10-1703) there is
            # no live function to carry the declaration. An unguarded getattr would ERROR with
            # AttributeError here instead of passing. A REQUIRED name is still a hard failure:
            # this must not become a blanket excuse for a missing declaration.
            assert qualified in conftest.OPTIONAL_WIN32, (
                f"{qualified} is not in OPTIONAL_WIN32 but is missing from the live user32"
            )
            continue
        assert func.argtypes is not None, f"{qualified} has no argtypes on the live function"
        assert len(func.argtypes) == len(argtypes), f"{qualified} argtype count disagrees"
        assert func.restype is not None, f"{qualified} has no restype"
        # Pointer-sized returns must actually be pointer-sized: the default restype is a
        # 32-bit int, which would truncate and sign-extend an LRESULT.
        if _restype in ("LRESULT", "HANDLE", "HWND", "DWORD_PTR"):
            assert ctypes.sizeof(func.restype) == ctypes.sizeof(ctypes.c_void_p), (
                f"{qualified} returns {_restype} but its restype is only "
                f"{ctypes.sizeof(func.restype)} bytes wide"
            )
        # Every argtype the declaration calls HWND must be pointer-sized too.
        for position, declared_name in enumerate(argtypes):
            if declared_name in ("HWND", "HANDLE", "WPARAM", "LPARAM"):
                assert ctypes.sizeof(func.argtypes[position]) == ctypes.sizeof(ctypes.c_void_p), (
                    f"{qualified} argument {position} is declared {declared_name} but is only "
                    f"{ctypes.sizeof(func.argtypes[position])} bytes wide"
                )
    # And the handle must be our own, not the shared windll cache.
    assert conftest.USER32 is not ctypes.windll.user32, (
        "the tier must own its user32 handle so its argtypes are not process-wide"
    )
    hwnd_type = conftest.USER32.IsWindowVisible.argtypes[0]
    assert ctypes.sizeof(hwnd_type) == ctypes.sizeof(ctypes.c_void_p), (
        "HWND must be declared pointer-sized"
    )
