# Sinclair QL for [MiSTer Board](https://github.com/MiSTer-devel/Main_MiSTer/wiki) 

This is port from [MiST](https://github.com/mist-devel/mist-board/tree/master/cores/ql)

### Additional features implemented:
* Turbo modes (x2,x4)
* 896K of RAM
* RTC

### Note:
This core should support secondary SD card, but i couldn't find a working combination of SD card format and ROM. Need further testing.

### Installation:
* Copy the *.rbf file at the root of the SD card. 
* Copy boot.rom into QL folder.
* Copy some *.mdv files to QL folder.


## Original ReadMe

Sinclair QL core for the MIST board

This core needs a QL rom image on SD card named ql.rom in the SD cards
root directory. It's known to work with Minerva ROM 1.98 as well as the
original js.rom. Other ROMs may work as well. The ROM size must be exaclty
49152 bytes. Minerva and other roms are available as a free download from 
http://www.dilwyn.me.uk/qlrom/.

It is possible to add another 16k of extension ROM. The resulting size
of the ROM image should then be 65536 bytes. E.g. the Toolkit-2 ROM is
available for download at http://www.dilwyn.me.uk/pe. The necessary
combination of both ready-to-use is available 
[here](https://github.com/MiSTer-devel/QL_MiSTer/tree/master/releases).

The core implements the complete 8049 IPC controller and thus fully
supports all keybaord monitoring modes as well as joysticks and audio.

Files can be loaded from microdrive images stored in MDV files in QLAY
format. Thee files must be exactly 174930 bytes in size. Examples can
be found in http://web.inter.nl.net/hcc/A.Jaw.Venema/psion.zip as well as
in the [releases](https://github.com/MiSTer-devel/QL_MiSTer/tree/master/releases) directory.

If a matching ql.rom is being used the built-in [QL-SD](http://www.dilwyn.me.uk/qlsd/index.html) allows to directly access a huge image file stored
on SD card.
