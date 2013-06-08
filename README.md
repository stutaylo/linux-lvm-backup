Linux LVM Backup Script.
========================

Shell script to backup Linux volume via LVM snapshots, and scp's it 
across to a secondary host (assumes keyswaps etc. are in place and that
remote directory exists).

./linux\_backup.sh /data foo@boo.server:/backup

Written as a quick fix for some stuff I needed. I probably need to revisit
this if I was to ever use it in anger, does the trick though.
