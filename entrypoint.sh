#!/bin/sh

case $1 in
  scheduler) ruby scheduler.rb ;;
  queue) bundle exec sidekiq -r ./lib/queue/tasks.rb -i $2 ;;
  web) bundle exec thin start -a 0.0.0.0 -p $2 ;;
  *) echo "Unsupported command $1"
esac
