#!/bin/bash

export SEGMENT=`hadoop fs -ls crawl/segments/ | grep segments |  sed -e "s/\//\\n/g" | egrep 20[0-9]+ | sort -n | tail -n 1`
echo "Operating on segment : $SEGMENT"
