require 'bundler/setup'
# install bundler managed deps
require 'sqlite3'
require 'gtk3'
require 'xdg'
require 'rexml/document'
require 'rexml/streamlistener'
# so normal require works in scripts
Bundler.reset_rubygems!
require 'cabal/version'
require 'cabal/init'
