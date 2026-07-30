# Engine patch set

Patch order for the CX26.3 / Wine 11.0 Cyder007 engine:

1. `cyder-compatdb-runtime.patch`
2. `wine-11.1-rtlwalkframechain-null-function.patch`
3. `cyder-ntdll-frame-walk-page-fault-guard.patch`

`wine-11.1-rtlwalkframechain-null-function.patch` is the minimal upstream
Wine 11.1–11.14 behavior backport: stop x86_64 frame walking when no runtime
function entry exists.

`cyder-ntdll-frame-walk-page-fault-guard.patch` is the narrowly scoped Cyder
addition for non-null but unreadable or concurrently invalidated unwind
metadata.

`obsolete/cyder-ntdll-frame-walk-guard.patch` is retained only to migrate an
incremental Cyder006 source tree. It is removed before the two replacement
patches are applied.

`cyder-steam-webhelper-compat.patch` is likewise retained only so the build can
remove the obsolete executable-specific patch before applying the generic
CompatDB runtime.

The frame-walk patches are intentionally CX26-only. CX25 uses a Wine 10 base and
must not receive them without a separate source and ABI review.

