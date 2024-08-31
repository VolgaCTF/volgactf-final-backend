#!/bin/sh

case $1 in
  scheduler) ruby scheduler.rb ;;
  *) echo "Unsupported command $1"
esac
