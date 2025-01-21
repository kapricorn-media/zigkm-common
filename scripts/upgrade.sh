#!/bin/bash -e

org=kapricorn-media
repo=${PWD##*/}

echo Backing up $repo...
if [ -d "./$repo-bak" ]
then
    if [ -d "./$repo-bak2" ]
    then
        rm -rf "./$repo-bak2"
    fi
    mv "./$repo-bak" "./$repo-bak2"
fi
mv "./$repo" "./$repo-bak"

echo Downloading latest release artifact from $org/$repo...
curl -o latest.zip "https://ci.kapricornmedia.com/latest_artifact?org=$org&repo=$repo"
unzip -o latest.zip
tar -xf output_archive.tar.gz
if [ -d "./$repo" ]
then
    echo Download succeeded.
else
    echo Download+extract failed, aborting...
    mv "./$repo-bak" "./$repo"
    exit 1
fi

if [ -d "./$repo-bak/keys" ]
then
    echo Copying keys...
    cp -r "./$repo-bak/keys" "./$repo/keys"
fi
if [ -d "./$repo-bak/state" ]
then
    echo Copying state...
    cp -r "./$repo-bak/state" "./$repo/state"
fi

echo Restarting service...
sudo systemctl restart $repo
echo Showing service status...
sudo systemctl status $repo
