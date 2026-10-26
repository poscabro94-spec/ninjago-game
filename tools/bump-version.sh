#!/bin/sh
# Sets src/ReplicatedStorage/GameVersion.luau to the build number of the next commit (commit count + 1)
# and today's date. Run it right before committing an update.
cd "$(dirname "$0")/.." || exit 1
n=$(( $(git rev-list --count HEAD) + 1 ))
d=$(date +%Y-%m-%d)
sed -i -e "s/Build = [0-9]*/Build = $n/" -e "s/Date = \"[^\"]*\"/Date = \"$d\"/" src/ReplicatedStorage/GameVersion.luau
echo "build $n ($d)"
