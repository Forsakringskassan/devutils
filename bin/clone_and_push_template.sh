#!/bin/bash

echo This script takes a template repo and an empty repo as arguments. It clones the template and pushes
echo the latest revision from the template as a new commit in the empty repo.
echo
echo Example:
echo
echo  clone_and_push_template.sh \<jar\|api\|quarkus\|kubernetes\> https://github.com/Forsakringskassan/the_new_repo.git
echo

if [ -z "$1" ]
then
    echo "Missing template"
    exit
fi
tmplrepo=$1
if [ "$tmplrepo" == "jar" ]; then
    tmplrepo=git@github.com:Forsakringskassan/template-jar.git
fi
if [ "$tmplrepo" == "api" ]; then
    tmplrepo=git@github.com:Forsakringskassan/template-api.git
fi
if [ "$tmplrepo" == "quarkus" ]; then
    tmplrepo=git@github.com:Forsakringskassan/template-quarkus.git
fi
if [ "$tmplrepo" == "kubernetes" ]; then
    tmplrepo=git@github.com:Forsakringskassan/template-kubernetes.git
fi

echo "Using $tmplrepo"

if [ -z "$2" ]
then
    echo "Missing new repo"
    exit
fi
newrepo=$2
TMPFOLDER=$(mktemp -d)

echo "Pushing to $newrepo and working in $TMPFOLDER"

git clone $newrepo $TMPFOLDER \
&& cd $TMPFOLDER \
&& git remote add tmpl $tmplrepo \
&& git fetch tmpl \
&& git checkout tmpl/master . \
&& echo "" > CHANGELOG.md \
&& git add . \
&& tmpl_ref=`git rev-parse tmpl/master` \
&& git commit -a -m "chore: Initialize with $tmplrepo $tmpl_ref" \
&& git push -u origin master \
&& cd ..
