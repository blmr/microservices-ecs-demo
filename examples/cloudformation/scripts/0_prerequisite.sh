#!/bin/bash
# Prerequisite: AWS CLI 0.11 and later, JQ 1.3 and later

#Install pip
wget https://bootstrap.pypa.io/get-pip.py
python get-pip.py

#Install awscli
pip install awscli

#Install jq
apt-get install jq
#yum install jq
