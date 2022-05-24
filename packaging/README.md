# Packaging Scripts

## generate-deps.sh
This script is used to generate a list of dependent packages from a list of shell commands. All dependent packages must be installed on the system running the script, as querying the repo directly will give too many conflicting alternatives. If any commands provided   
The script will print just the list of packages to stdout, and will print more information to stderr.  
Works on Debian-like and RHEL-like systems.  
```
./generate-deps.sh command-dependencies.txt > package-dependencies.txt
# or
cat command-dependencies.txt | ./generate-deps.sh > package-dependencies.txt
# or
cat <<EOF | ./generate-deps.sh > package-dependencies.txt
getent
wbinfo
exportfs
stat
mkdir
chown
chgrp
chmod
ls
net
realm
smbcontrol
mktemp
dd
rm
getfattr
setfattr
df
systemctl
EOF
```
