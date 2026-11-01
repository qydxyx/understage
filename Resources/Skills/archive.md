---
id: archive
title: Zip and organize
match: zip,png,jpg,jpeg,pdf,mp4,mov
---

- Zip: `/usr/bin/zip -r archive.zip files...` with cwd the Finder folder.
- Unzip: `/usr/bin/ditto -x -k archive.zip destFolder` into a new unique folder.
- Organize only when the user asks to sort or organize. Otherwise do not move files into type folders.
