require 'cabal/eaccess'

module Cabal
  class CLI
    class Developer < Thor
      desc 'pem', 'fetch the peer certificate from eaccess SSL gateway'
      def pem
        EAccess.download_pem
        puts "wrote peer certificate to %s" % EAccess::PEM
      end
    end
  end
end
