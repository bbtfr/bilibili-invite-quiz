#!/usr/sh

rm -rf _posts
git checkout master db/html
mv db/html _posts
rm -r db
