#!/bin/sh
# Name: Dashboard Test
# Author: pusi77
# DontUseFBInk
mkdir -p /mnt/us/dashboard/logs
exec sh /mnt/us/dashboard/dash.sh once >>/mnt/us/dashboard/logs/test.log 2>&1
