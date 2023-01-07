#!/bin/bash

docker build -t rackdav . && docker run -it rackdav rspec
