#!/bin/bash

# List of software packages to check
packages=(nginx htop curl wget)

# Loop through the packages array
for package in "${packages[@]}"; do
  # Check if the package is installed
  dpkg -s $package &> /dev/null
  if [ $? -eq 0 ]; then
    echo "$package is installed"
  else
    echo "$package is not installed"
  fi
done
