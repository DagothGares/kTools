kTools outputs a database of JSON files, with each record being contained in a single file. Each record type has its' own folder; activators are stored in ACTI, factions in FACT, and so on. For quickly iterating over/searching all records of a given type without querying the filesystem, there are a set of 'lists' contained in <output>/list, with each file being an array of filenames for a given record type.

All record names and strings are translated to UTF-8. Specific output depends on the Windows codepage you select when running kTools; by default, it chooses Windows-1252, which is the Latin codepage. All strings are also trimmed of their null byte endings.

Record names also have the following characters replaced, so they can serve as valid filenames:

  ``< > " | * ? \r \n \t`` (replaced with ``_``)

  ``.`` (replaced with ``,``)

  ``:`` (replaced with ``;``

Note that slashes and backslashes are not replaced; it wasn't necessary to remove them, so you can occasionally see paths such as ``LEVI/t_mw_random_foodm1/2.json``.

The format of each record type mostly matches up with what's shown in [the uesp](https://en.uesp.net/wiki/Morrowind_Mod:Mod_File_Format), though there are some deviations.
One major deviation across all record types is that kTools does not store most record flags. All valid flags are stored at the top level of a record / form reference with the following field names:

  ``deleted``

  ``persistent`` (for record types that can be used for FRMRs; note that you can ignore this field entirely if you are running OpenMW)

  ``initially_disabled`` (for FRMRs; note that you can ignore this field entirely, at is irrelevant in Morrowind)

  ``blocked`` (for FRMRs; note that you can ignore this field entirely, as it is irrelevant in Morrowind)

Another major deviation across all record types is that files do not store their identifiers, since you get that automatically from the filename. The only exceptions to this are CELLs, since exteriors can have a display name stored, which means interiors also store a copy of their name (minus the sanitization necessary to make them valid filenames).

The last major deviation across all record types that I'll mention is that all field names that are not referencing a subrecord type are in ``snake_case``. For example, ``CELL:AMBI`` looks like:
  ```json
  {
    "ambient": [71,71,71,0],
    "sunlight": [70,70,70,0],
    "fog_color": [0,0,0,0],
    "fog_density": 1
  }
  ```

As far as the field names for structs in individual records (and whether or not subrecords are guaranteed to exist for a given subrecord, you can check ``src/rec/`` and see the structure for records yourself. For example, ``ACTI`` has the following fields:
```zig
flag: u2, // this gets turned into 'deleted' and 'persistent' in the output
MODL: []const u8 = undefined, // this is a guaranteed field, that is stored as a string
FNAM: []const u8 = undefined, // same as above
SCRI: ?[]const u8 = null, // This is an optional field, so be sure to check if it exists before using it for a given record!
```
The only major deviations from this form that I can think of offhand are that fields prefixed ``_garbage`` are not stored in the output, and that some types of subrecords are stored as Objects instead of Arrays. ``ARMO:INDX`` and ``CLOT:INDX`` both look like this:
```json
"INDX": {
  "16": {
    "bnam": "a_adamantium_boot_f",
    "cnam": null
  },
  "18": {
    "bnam": "a_adamantium_boot_a",
    "cnam": null
  },
  "15": {
    "bnam": "a_adamantium_boot_f",
    "cnam": null
  },
  "17": {
    "bnam": "a_adamantium_boot_a",
    "cnam": null
  }
}
```
where each key is an INDX (biped slot) and the values are BNAM and/or CNAM fields (part model names).
``FACT:ANAM`` looks like this:
```json
"ANAM": {
  "Ashlanders": 3,
  "Sixth House": -3,
  "Thieves Guild": -2,
  "Imperial Legion": -2,
  "Fighters Guild": -2,
  "Clan Quarra": -3,
  "Clan Berne": -3,
  "Clan Aundae": -3,
  "Camonna Tong": -1,
  "Telvanni": -1,
  "Hlaalu": -2,
  "Redoran": -2,
  "Temple": -1,
  "Blades": -1,
  "Imperial Cult": -1,
  "Mages Guild": -1
}
```
where each key is the name of another faction, and the value is the INTV subrecord that would normally follows (indicating that faction's 'reaction' to the faction record you're looking at).

``CREA`` and ``NPC_`` have an ``AI_`` array, which is a union type of ``AI_A``, ``AI_E``, ``AI_F``, ``AI_T``, and ``AI_W``. In JSON, they look, for example, like this:
```json
"AI_": [
  {
    "ai_type": "W",
    "distance": 1000,
    "duration": 0,
    "time_of_day": 0,
    "idles": [50,50,0,0,0,0,0,0]
  },
  {
    "ai_type": "F",
    "core": {
      "position": [3.40282346e+38,3.40282346e+38,3.40282346e+38],
      "duration": 0,
      "name": "TR_m4_TJ_Scamp_Crtyrd_1"
    },
    "CNDT": null
  },
  {
    "ai_type": "F",
    "core": {
      "position": [3.40282346e+38,3.40282346e+38,3.40282346e+38],
      "duration": 0,
      "name": "TR_m4_TJ_Scamp_Crtyrd_2"
    },
    "CNDT": null
  },
  {
    "ai_type": "F",
    "core": {
      "position": [3.40282346e+38,3.40282346e+38,3.40282346e+38],
      "duration": 0,
      "name": "TR_m4_TJ_Scamp_Crtyrd_3"
    },
    "CNDT": null
  }
]
```
Note that the definition of the union type is ``AI__``, which can be found in ``src/rec/shared.zig``.

Lastly, form references ``CELL:FRMR`` are stored as a hashmap. For example:
```json
 "FRMR": {
    "8-461183": {
      "deleted": false,
      "persistent": true,
      "initially_disabled": false,
      "blocked": false,
      "NAME": "TR_m2_Brelyna_Thindo",
      "DATA": [-15.84907341003418,9.183551788330078,-99.12727355957031,0,0,1.9000003337860107]
    },
    "8-461184": {
      "deleted": false,
      "persistent": true,
      "initially_disabled": false,
      "blocked": false,
      "NAME": "in_de_shack_door",
      "ANAM": "TR_m2_Brelyna_Thindo",
      "INTV": 0,
      "NAM9": 1,
      "DATA": [187.9648895263672,-63.76250076293945,-33.103424072265625,0,0,4.71238899230957]
    },
    "8-461185": {
      "deleted": false,
      "persistent": false,
      "initially_disabled": false,
      "blocked": false,
      "NAME": "in_de_shack_05",
      "DATA": [0,0,0,0,0,0]
    },
    "8-461186": {
      "deleted": false,
      "persistent": false,
      "initially_disabled": false,
      "blocked": false,
      "NAME": "active_de_bed_30",
      "ANAM": "TR_m2_Brelyna_Thindo",
      "INTV": 0,
      "NAM9": 1,
      "DATA": [13.563163757324219,83.73147583007812,-19.368783950805664,0,0,0]
    }
}
```
Note the format of each key; for example, ``8-461183``. If you're familiar with TES3MP, you might think that this is a uniqueIndex. This isn't the case. What this actually is, is ``masterIndex-FRMR``, where ``FRMR`` is the actual form reference value stored in the ESM/ESP that the entry was taken from, and ``masterIndex`` is the position of the plugin the entry was taken from in your load order. For example, if I were to load ``Morrowind.esm``, ``Tribunal.esm``, and ``Bloodmoon.esm``, a form reference from Morrowind would look like ``0-1234``, one from Tribunal would look like ``1-1234``, and one from Bloodmoon would look like ``2-1234``. If I was to rearrange my load order so it was ``Morrowind.esm``, ``Bloodmoon.esm``, and then ``Tribunal.esm`` instead, form references from Bloodmoon would instead start with ``1-``, and Tribunal references would start with ``2-``.
