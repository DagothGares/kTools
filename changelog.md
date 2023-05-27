## 0.1.2:
Overhauled the way record parsing works, to better mirror how Morrowind.exe and the TES-CS handle records. See FORMAT.md.
kTools now emits warnings for unrecognized subrecord fields, instead of exiting. Warning messages may be surpressed by setting ``--log-level=1`` or 0.

### Known issues:
If a subrecord is expected to be found as part of a pair (for example, ``CREA:DODT`` expects a ``CREA:DNAM``), but kTools instead finds an unknown subrecord type, it will emit two 'unknown subrecord type' warnings instead of one.

## 0.1.1:
Fixed an issue where CREA:AI_ and NPC_:AI_ were writing AI packages without marking the package type.
FORMAT.md and changelog.md are now bundled with releases.

## 0.1.0:
Initial release.
