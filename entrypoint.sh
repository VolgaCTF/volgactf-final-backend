#!/bin/sh

command_arg=$1
shift

case $command_arg in
  scheduler) ruby scheduler.rb ;;
  queue) bundle exec sidekiq -r ./lib/queue/tasks.rb -i $1 ;;
  web) bundle exec thin start -a 0.0.0.0 -p $1 ;;
  cli) bundle exec rake "$@" ;;
  *) echo "Unsupported command $command_arg"
esac
