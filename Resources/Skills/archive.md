---
id: archive
title: Zip and organize
match: zip,png,jpg,jpeg,pdf,mp4,mov
---

- Zip: `/usr/bin/zip -r archive.zip files...` with cwd the Finder folder.
- Unzip: `/usr/bin/ditto -x -k archive.zip destFolder` into a new unique folder.
- Organize by type: create `Images`, `Videos`, `Documents` in the current folder, then `move` files. Skip if a folder with that name already holds the file.
