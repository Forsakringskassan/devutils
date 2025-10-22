#!/bin/bash
#
# The idea is that you can add something like this:
#
#  source ~/path/to/this/file.sh
#
# In your ~/.bashrc
#
echo " ________________________________________________________"
echo \|
echo \| Using Devutils:
echo \|  https://github.com/Forsakringskassan/devutils
echo \|________________________________________________________
echo

git -C ~/devutils pull -q > /dev/null 2>&1

export PATH=~/devutils/bin:$PATH
