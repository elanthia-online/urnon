require 'bundler/setup'
# install bundler managed deps
require 'sequel'
require 'gtk3'
require 'xdg'
require 'rexml/document'
require 'rexml/streamlistener'
# so normal require works in scripts
Bundler.reset_rubygems!

require 'urnon/version'
module Urnon
  class Error < StandardError; end
  # Your code goes here...
end
require 'urnon/init'
