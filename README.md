# kTools
kTools is a (work-in-progress) parser for Morrowind's ESM and ESP file format. It is capable of representing a given Morrowind load order as a database of JSON files, with each file making up a record.

## Building
You need:
- A build of Zig 0.11, which you can get from either [the main site](https://ziglang.org/download/) or by using [zigup](https://github.com/marler8997/zigup)
- (optional) [git](https://git-scm.com/), to grab the necessary [zig-args](https://github.com/MasterQ32/zig-args) submodule

### Using git:

``git clone https://github.com/DagothGares/kTools.git --recurse-submodules``

``zig build -Doptimize=ReleaseSafe`` (the available options are Debug, ReleaseSafe (recommended), ReleaseSmall, and ReleaseFast)

### Manually:
Hit the green 'Code' button -> Download zip.

Get [zig-args](https://github.com/MasterQ32/zig-args) from its' repo and put it in ``lib/zig-args``.

``zig build -Doptimize=ReleaseSafe`` (the available options are Debug, ReleaseSafe (recommended), ReleaseSmall, and ReleaseFast)

## Using kTools
Make a json file that contains an array of plugin paths and hashes, like so:
```json
[
    {"drive:\\path-to\\Morrowind.esm": ["0x7B6AF5B9"]},
    {"/path-to/Tribunal.esm": ["0xF481F334"]},
    {"/path-to/Bloodmoon.esm": ["0x43DD2132"]}
]
```
The first line is an example Windows path, while the latter two are example Linux paths.

The astute may recognize that this matches the format of TES3MP's requiredDataFiles.json; it is valid to copy and paste that to use it as a template.

It is recommended to use full paths. (Start from the drive letter on Windows, or the root directory ``/`` on Linux)

Note that while you are allowed to specify multiple hashes for each file, only the first hash is checked, to ensure that the data generated is authoritative.

Then, run ``kTools <load_order.json> <output_directory>``, where ``<load_order.json>`` is the json file you created, and ``<output_directory>`` is where you want the database to be generated (preferably, an empty directory).

Note that you will need to change what codepage you are using, if you are reading plugins with non-Latin text. You can set the codepage by defining the ``--codepage`` option when running kTools.

``kTools --help`` outputs a help page showing available commands and settings.

## Reading the output
see FORMAT.md
