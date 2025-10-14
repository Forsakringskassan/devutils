# Devutils

A collection of scripts for developers.

## Install

The idea is that you clone this repo And point to it with your `~/.bashrc`.

```sh
git clone git@github.com:Forsakringskassan/template-kubernetes.git ~/devutils \
 && echo "source ~/devutils/bashrc.sh" >> ~/.bashrc \
 && source ~/.bashrc
```

## Development

All scripts added should be executable.

```sh
git update-index --chmod=+x bin/*
```
