#!/bin/sh

case $1 in
  scheduler) ruby scheduler.rb ;;
  queue) bundle exec sidekiq -r ./lib/queue/tasks.rb -i $2 ;;
  *) echo "Unsupported command $1"
esac
