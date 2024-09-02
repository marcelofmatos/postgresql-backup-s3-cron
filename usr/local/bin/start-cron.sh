#!/bin/sh

echo "Current crontabs:"
cat /etc/crontabs/*

echo "Cron service started"
exec crond -f -l 2
